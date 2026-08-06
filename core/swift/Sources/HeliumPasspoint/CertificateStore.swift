import Foundation
import Security

/// X.509 helpers built on the Security framework plus a small DER reader for
/// the one field `SecCertificate` will not expose on iOS.
enum CertificateStore {
  /// Parse a PEM certificate. Tolerates CRLF, missing trailing newline and
  /// arbitrary whitespace inside the base64 body.
  static func parsePEM(_ pem: String) -> SecCertificate? {
    guard let data = derData(fromPEM: pem) else { return nil }
    return SecCertificateCreateWithData(nil, data as CFData)
  }

  /// Strip PEM armour and decode the base64 payload to DER.
  static func derData(fromPEM pem: String) -> Data? {
    let body =
      pem
      .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
      .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
    return Data(base64Encoded: body, options: .ignoreUnknownCharacters)
  }

  static func subjectSummary(of certificate: SecCertificate) -> String? {
    SecCertificateCopySubjectSummary(certificate) as String?
  }

  /// `SecCertificateCopyValues` is macOS-only, so on iOS the notAfter field is
  /// read straight out of the DER.
  static func expirationDate(of certificate: SecCertificate) -> Date? {
    guard let data = SecCertificateCopyData(certificate) as Data? else { return nil }
    return notAfter(derEncoded: data)
  }

  /// Extract `tbsCertificate.validity.notAfter` from a DER-encoded X.509
  /// certificate.
  ///
  /// ```
  /// Certificate ::= SEQUENCE {
  ///   tbsCertificate SEQUENCE {
  ///     version [0] EXPLICIT INTEGER OPTIONAL,
  ///     serialNumber INTEGER,
  ///     signature AlgorithmIdentifier,
  ///     issuer Name,
  ///     validity SEQUENCE { notBefore Time, notAfter Time },
  ///     ... } ... }
  /// ```
  static func notAfter(derEncoded data: Data) -> Date? {
    let bytes = [UInt8](data)
    var offset = 0

    guard enterSequence(bytes, offset: &offset) else { return nil }  // Certificate
    guard enterSequence(bytes, offset: &offset) else { return nil }  // tbsCertificate

    // version [0] EXPLICIT — optional, present in every v3 certificate
    if offset < bytes.count, bytes[offset] == 0xA0 {
      guard skipTLV(bytes, offset: &offset) else { return nil }
    }
    guard skipTLV(bytes, offset: &offset) else { return nil }  // serialNumber
    guard skipTLV(bytes, offset: &offset) else { return nil }  // signature
    guard skipTLV(bytes, offset: &offset) else { return nil }  // issuer

    guard enterSequence(bytes, offset: &offset) else { return nil }  // validity
    guard skipTLV(bytes, offset: &offset) else { return nil }  // notBefore
    return readTime(bytes, offset: &offset)
  }

  // MARK: - DER reading

  /// Step over a tag+length header, leaving `offset` at the first content byte.
  private static func enterSequence(_ bytes: [UInt8], offset: inout Int) -> Bool {
    guard offset < bytes.count, bytes[offset] == 0x30 else { return false }
    offset += 1
    return readLength(bytes, offset: &offset) != nil
  }

  /// Step over an entire tag+length+value.
  private static func skipTLV(_ bytes: [UInt8], offset: inout Int) -> Bool {
    guard offset < bytes.count else { return false }
    offset += 1
    guard let length = readLength(bytes, offset: &offset) else { return false }
    guard length <= bytes.count - offset else { return false }
    offset += length
    return true
  }

  private static func readLength(_ bytes: [UInt8], offset: inout Int) -> Int? {
    guard offset < bytes.count else { return nil }
    let first = bytes[offset]
    offset += 1
    if first & 0x80 == 0 { return Int(first) }

    let count = Int(first & 0x7F)
    // 0x80 is the indefinite form, illegal in DER; >8 bytes cannot fit an Int.
    guard count > 0, count <= 8, offset + count <= bytes.count else { return nil }
    var length = 0
    for index in 0..<count {
      length = (length << 8) | Int(bytes[offset + index])
    }
    offset += count
    guard length >= 0 else { return nil }
    return length
  }

  /// Read a `UTCTime` (tag 0x17) or `GeneralizedTime` (tag 0x18).
  private static func readTime(_ bytes: [UInt8], offset: inout Int) -> Date? {
    guard offset < bytes.count else { return nil }
    let tag = bytes[offset]
    offset += 1
    guard let length = readLength(bytes, offset: &offset) else { return nil }
    guard length <= bytes.count - offset else { return nil }
    guard let string = String(bytes: bytes[offset..<(offset + length)], encoding: .ascii) else {
      return nil
    }
    offset += length

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    switch tag {
    case 0x17: formatter.dateFormat = "yyMMddHHmmss'Z'"  // UTCTime
    case 0x18: formatter.dateFormat = "yyyyMMddHHmmss'Z'"  // GeneralizedTime
    default: return nil
    }
    return formatter.date(from: string)
  }
}
