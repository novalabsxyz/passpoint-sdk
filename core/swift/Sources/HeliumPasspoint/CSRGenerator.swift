import Foundation
import Security
import os

/// An RSA keypair held in the keychain (or, in tests, in memory).
public struct SecKeyPair {
  public let privateKey: SecKey
  public let publicKey: SecKey

  public init(privateKey: SecKey, publicKey: SecKey) {
    self.privateKey = privateKey
    self.publicKey = publicKey
  }
}

/// Builds PKCS#10 Certificate Signing Requests using only the Security
/// framework — no Shield, OpenSSL or BoringSSL dependency.
///
/// This type is pure (given a keypair it does no I/O), which is what lets the
/// test suite generate a CSR and verify it with `openssl req -verify`.
struct CSRGenerator {
  /// The literal `DOMAIN` is a sentinel the HIB inventory service substitutes
  /// with the partner's first NAI realm when issuing the certificate.
  static func commonName(subscriberID: String) -> String {
    "anonymous@\(subscriberID).DOMAIN"
  }

  private let logger = Logger(subsystem: "com.helium.passpoint", category: "CSRGenerator")

  /// Returns a PEM-encoded PKCS#10 CSR.
  /// - Throws: ``PasspointError`` with code `CSR_GENERATION_FAILED`.
  func generate(subscriberID: String, keyPair: SecKeyPair) throws -> String {
    let commonName = Self.commonName(subscriberID: subscriberID)

    guard
      let publicKeyData = SecKeyCopyExternalRepresentation(keyPair.publicKey, nil) as Data?
    else {
      throw PasspointError.csrGenerationFailed("could not export public key")
    }

    // CertificationRequestInfo ::= SEQUENCE {
    //   version INTEGER, subject Name, subjectPKInfo SPKI, attributes [0] }
    let subject = DER.sequence(DER.set(DER.sequence(
      DER.oid(DER.OID.commonName) + DER.utf8String(commonName)
    )))
    let attributes = Data([0xA0, 0x00])  // empty attributes, [0] IMPLICIT

    let certRequestInfo = DER.sequence(
      DER.integer(0) + subject + spki(publicKeyData: publicKeyData) + attributes
    )

    guard let signature = sign(certRequestInfo, with: keyPair.privateKey) else {
      throw PasspointError.csrGenerationFailed("signing failed")
    }

    let csr = DER.sequence(
      certRequestInfo
        + DER.sequence(DER.oid(DER.OID.sha256WithRSA) + DER.null())
        + DER.bitString(signature)
    )

    // One unbroken line, matching the Kotlin SDK. `.lineLength64Characters`
    // wraps with CRLF, which is legal PEM but made the two platforms emit
    // structurally different requests for the same input.
    let base64 = csr.base64EncodedString()
    return "-----BEGIN CERTIFICATE REQUEST-----\n\(base64)\n-----END CERTIFICATE REQUEST-----"
  }

  // MARK: - Private

  private func sign(_ data: Data, with privateKey: SecKey) -> Data? {
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) as Data?
    else {
      if let err = error?.takeRetainedValue() {
        logger.warning("sign: \(err.localizedDescription, privacy: .public)")
      }
      return nil
    }
    return signature
  }

  /// SubjectPublicKeyInfo ::= SEQUENCE { algorithm AlgorithmIdentifier, subjectPublicKey BIT STRING }
  ///
  /// `SecKeyCopyExternalRepresentation` returns a PKCS#1 `RSAPublicKey`, which
  /// is exactly what belongs inside the BIT STRING for `rsaEncryption`.
  private func spki(publicKeyData: Data) -> Data {
    let algorithm = DER.sequence(DER.oid(DER.OID.rsaEncryption) + DER.null())
    return DER.sequence(algorithm + DER.bitString(publicKeyData))
  }
}

/// Minimal ASN.1 DER writer. Internal so the unit tests can assert the encoding
/// rules directly rather than only through a full CSR.
enum DER {
  enum OID {
    static let commonName = Data([0x55, 0x04, 0x03])
    static let rsaEncryption = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    static let sha256WithRSA = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
  }

  /// Definite-length encoding, short form below 128 and long form above, using
  /// the minimum number of length bytes as DER requires.
  static func length(_ length: Int) -> Data {
    if length < 0x80 { return Data([UInt8(length)]) }

    var bytes: [UInt8] = []
    var remaining = length
    while remaining > 0 {
      bytes.insert(UInt8(remaining & 0xFF), at: 0)
      remaining >>= 8
    }
    return Data([0x80 | UInt8(bytes.count)] + bytes)
  }

  static func tlv(tag: UInt8, _ content: Data) -> Data {
    Data([tag]) + length(content.count) + content
  }

  static func sequence(_ content: Data) -> Data { tlv(tag: 0x30, content) }
  static func set(_ content: Data) -> Data { tlv(tag: 0x31, content) }
  static func oid(_ oid: Data) -> Data { tlv(tag: 0x06, oid) }
  static func utf8String(_ string: String) -> Data { tlv(tag: 0x0C, Data(string.utf8)) }
  static func null() -> Data { Data([0x05, 0x00]) }

  /// BIT STRING with zero unused trailing bits.
  static func bitString(_ data: Data) -> Data { tlv(tag: 0x03, Data([0x00]) + data) }

  /// Non-negative INTEGER in minimal two's-complement form. A leading `0x00` is
  /// added when the top bit would otherwise mark the value as negative.
  static func integer(_ value: Int) -> Data {
    precondition(value >= 0, "DER.integer only encodes non-negative values")
    if value == 0 { return tlv(tag: 0x02, Data([0x00])) }

    var bytes: [UInt8] = []
    var remaining = value
    while remaining > 0 {
      bytes.insert(UInt8(remaining & 0xFF), at: 0)
      remaining >>= 8
    }
    if bytes[0] & 0x80 != 0 { bytes.insert(0x00, at: 0) }
    return tlv(tag: 0x02, Data(bytes))
  }
}
