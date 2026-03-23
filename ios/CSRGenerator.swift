import Foundation
import Security
import os

/// Generates PKCS#10 Certificate Signing Requests using only the Security framework.
/// No external dependencies (Shield, OpenSSL, etc.) required.
class CSRGenerator {
  private let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  func generate(userIdentifier: String, domain: String, keyPair: SecKeyPair) -> String? {
    #if !targetEnvironment(simulator)
      logger.info("generateCSR: for user \(userIdentifier, privacy: .public)")

      let cn = "anonymous@\(userIdentifier).\(domain)"

      guard let publicKeyData = SecKeyCopyExternalRepresentation(keyPair.publicKey, nil) as Data? else {
        logger.warning("generateCSR: failed to export public key")
        return nil
      }

      // Build CertificationRequestInfo DER
      let subject = derSequence(derSet(derSequence(
        derOID(OID.commonName) + derUTF8String(cn)
      )))
      let spki = buildSPKI(publicKeyData: publicKeyData)
      let attributes = Data([0xA0, 0x00]) // empty attributes [0] IMPLICIT

      let certRequestInfo = derSequence(
        derInteger(0) +   // version v1(0)
        subject +
        spki +
        attributes
      )

      // Sign CertificationRequestInfo with SHA256withRSA
      guard let signature = sign(data: certRequestInfo, with: keyPair.privateKey) else {
        logger.warning("generateCSR: signing failed")
        return nil
      }

      // Build full CertificationRequest
      let csr = derSequence(
        certRequestInfo +
        derSequence(derOID(OID.sha256WithRSA) + derNull()) + // signatureAlgorithm
        derBitString(signature)
      )

      let base64 = csr.base64EncodedString(options: .lineLength64Characters)
      let pem = "-----BEGIN CERTIFICATE REQUEST-----\n\(base64)\n-----END CERTIFICATE REQUEST-----"
      logger.info("generateCSR: success")
      return pem
    #else
      logger.warning("generateCSR: simulator build, skipping")
      return nil
    #endif
  }

  // MARK: - Signing

  private func sign(data: Data, with privateKey: SecKey) -> Data? {
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      privateKey,
      .rsaSignatureMessagePKCS1v15SHA256,
      data as CFData,
      &error
    ) as Data? else {
      if let err = error?.takeRetainedValue() {
        logger.warning("sign: \(err.localizedDescription, privacy: .public)")
      }
      return nil
    }
    return signature
  }

  // MARK: - SubjectPublicKeyInfo

  private func buildSPKI(publicKeyData: Data) -> Data {
    // SubjectPublicKeyInfo ::= SEQUENCE {
    //   algorithm AlgorithmIdentifier,   -- rsaEncryption
    //   subjectPublicKey BIT STRING      -- DER-encoded RSAPublicKey
    // }
    let algorithmIdentifier = derSequence(derOID(OID.rsaEncryption) + derNull())
    return derSequence(algorithmIdentifier + derBitString(publicKeyData))
  }

  // MARK: - ASN.1 DER Encoding Helpers

  private enum OID {
    static let commonName = Data([0x55, 0x04, 0x03])
    static let rsaEncryption = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    static let sha256WithRSA = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
  }

  private func derLength(_ length: Int) -> Data {
    if length < 0x80 {
      return Data([UInt8(length)])
    } else if length <= 0xFF {
      return Data([0x81, UInt8(length)])
    } else {
      return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
    }
  }

  private func derTLV(tag: UInt8, _ content: Data) -> Data {
    return Data([tag]) + derLength(content.count) + content
  }

  private func derSequence(_ content: Data) -> Data {
    return derTLV(tag: 0x30, content)
  }

  private func derSet(_ content: Data) -> Data {
    return derTLV(tag: 0x31, content)
  }

  private func derOID(_ oid: Data) -> Data {
    return derTLV(tag: 0x06, oid)
  }

  private func derUTF8String(_ string: String) -> Data {
    return derTLV(tag: 0x0C, Data(string.utf8))
  }

  private func derInteger(_ value: Int) -> Data {
    return derTLV(tag: 0x02, Data([UInt8(value)]))
  }

  private func derBitString(_ data: Data) -> Data {
    // BIT STRING: first byte is number of unused bits (0)
    return derTLV(tag: 0x03, Data([0x00]) + data)
  }

  private func derNull() -> Data {
    return Data([0x05, 0x00])
  }
}
