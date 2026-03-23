import Foundation
import Security

class CertificateStore {

  static func parsePEM(_ pem: String) -> SecCertificate? {
    let cleaned = pem
      .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----\n", with: "")
      .replacingOccurrences(of: "\n-----END CERTIFICATE-----", with: "")
    guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
      return nil
    }
    return SecCertificateCreateWithData(nil, data as CFData)
  }

  static func subjectSummary(of certificate: SecCertificate) -> String? {
    return SecCertificateCopySubjectSummary(certificate) as String?
  }

  static func expirationDate(of certificate: SecCertificate) -> Date? {
    // SecCertificateCopyValues is macOS-only. On iOS we parse the DER structure
    // for the notAfter field. For simplicity, use the ObjC bridge to read the
    // certificate's "Not Valid After" key from its dictionary representation.
    if #available(iOS 15.0, *) {
      guard let data = SecCertificateCopyData(certificate) as Data? else { return nil }
      return parseDERNotAfter(from: data)
    }
    return nil
  }

  // Minimal DER parser to extract the notAfter date from an X.509 certificate.
  // X.509 structure: SEQUENCE { tbsCertificate SEQUENCE { version, serial, sig,
  //   issuer, validity SEQUENCE { notBefore, notAfter }, subject, ... } }
  private static func parseDERNotAfter(from data: Data) -> Date? {
    let bytes = [UInt8](data)
    var offset = 0

    // Skip outer SEQUENCE tag+length
    guard skipTag(bytes, offset: &offset) else { return nil }
    // Skip tbsCertificate SEQUENCE tag+length
    guard skipTag(bytes, offset: &offset) else { return nil }

    // version (context tag [0], optional but usually present)
    if offset < bytes.count, bytes[offset] == 0xA0 {
      guard skipTLV(bytes, offset: &offset) else { return nil }
    }
    // serialNumber INTEGER
    guard skipTLV(bytes, offset: &offset) else { return nil }
    // signature AlgorithmIdentifier SEQUENCE
    guard skipTLV(bytes, offset: &offset) else { return nil }
    // issuer Name SEQUENCE
    guard skipTLV(bytes, offset: &offset) else { return nil }

    // validity SEQUENCE { notBefore, notAfter }
    guard skipTag(bytes, offset: &offset) else { return nil }
    // notBefore - skip it
    guard skipTLV(bytes, offset: &offset) else { return nil }
    // notAfter - read it
    return readTime(bytes, offset: &offset)
  }

  // Skip a TLV (tag + length + value) and advance offset past it.
  private static func skipTLV(_ bytes: [UInt8], offset: inout Int) -> Bool {
    guard offset < bytes.count else { return false }
    offset += 1 // tag
    guard let length = readLength(bytes, offset: &offset) else { return false }
    offset += length
    return offset <= bytes.count
  }

  // Skip just the tag + length header (for SEQUENCE containers we want to enter).
  private static func skipTag(_ bytes: [UInt8], offset: inout Int) -> Bool {
    guard offset < bytes.count else { return false }
    offset += 1 // tag
    guard readLength(bytes, offset: &offset) != nil else { return false }
    return true
  }

  private static func readLength(_ bytes: [UInt8], offset: inout Int) -> Int? {
    guard offset < bytes.count else { return nil }
    let first = bytes[offset]
    offset += 1
    if first & 0x80 == 0 {
      return Int(first)
    }
    let numBytes = Int(first & 0x7F)
    guard offset + numBytes <= bytes.count else { return nil }
    var length = 0
    for i in 0..<numBytes {
      length = (length << 8) | Int(bytes[offset + i])
    }
    offset += numBytes
    return length
  }

  // Read a UTCTime or GeneralizedTime from the current offset.
  private static func readTime(_ bytes: [UInt8], offset: inout Int) -> Date? {
    guard offset < bytes.count else { return nil }
    let tag = bytes[offset]
    offset += 1
    guard let length = readLength(bytes, offset: &offset) else { return nil }
    guard offset + length <= bytes.count else { return nil }
    guard let str = String(bytes: bytes[offset..<(offset + length)], encoding: .ascii) else {
      return nil
    }
    offset += length

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")

    if tag == 0x17 {
      // UTCTime: YYMMDDHHMMSSZ
      formatter.dateFormat = "yyMMddHHmmss'Z'"
    } else if tag == 0x18 {
      // GeneralizedTime: YYYYMMDDHHMMSSZ
      formatter.dateFormat = "yyyyMMddHHmmss'Z'"
    } else {
      return nil
    }
    return formatter.date(from: str)
  }
}
