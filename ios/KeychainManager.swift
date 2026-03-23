import Foundation
import Security
import os

struct SecKeyPair {
  let privateKey: SecKey
  let publicKey: SecKey
}

class KeychainManager {
  private let applicationTag: Data
  private let certLabel: String
  private let accessGroup: String?
  private let logger: Logger
  private var lastKeyStatus: OSStatus?

  init(
    applicationTag: String = "com.helium.passpoint.rsa-key",
    certLabel: String = "HeliumPasspoint Cert",
    accessGroup: String? = nil,
    logger: Logger
  ) {
    self.applicationTag = applicationTag.data(using: .utf8)!
    self.certLabel = certLabel
    self.accessGroup = accessGroup
    self.logger = logger
  }

  // MARK: - Keypair

  func getOrCreateKeyPair() -> SecKeyPair? {
    if let existing = getKeyPair() {
      return existing
    }
    return createKeyPair()
  }

  func deleteKeyPair() {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: applicationTag,
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
    ]
    addAccessGroup(to: &query)
    let status = SecItemDelete(query as CFDictionary)
    logger.info("deleteKeyPair: status \(status, privacy: .public)")
  }

  // MARK: - Certificates

  func saveCertificate(_ pem: String, label: String) -> SecCertificate? {
    #if !targetEnvironment(simulator)
      let cleaned = pem
        .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----\n", with: "")
        .replacingOccurrences(of: "\n-----END CERTIFICATE-----", with: "")
      guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
        logger.warning("saveCertificate: base64 decode failed for \(label, privacy: .public)")
        return nil
      }
      guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
        logger.warning("saveCertificate: SecCertificateCreateWithData failed for \(label, privacy: .public)")
        return nil
      }

      var query: [String: Any] = [
        kSecClass as String: kSecClassCertificate,
        kSecValueRef as String: certificate,
        kSecAttrLabel as String: label,
      ]
      addAccessGroup(to: &query)

      let status = SecItemAdd(query as CFDictionary, nil)
      if status == errSecDuplicateItem {
        logger.info("saveCertificate: duplicate for \(label, privacy: .public), fetching existing")
        return fetchCertificate(label: label) ?? certificate
      }
      if status != errSecSuccess {
        logger.warning("saveCertificate: SecItemAdd status \(status, privacy: .public) for \(label, privacy: .public)")
      }
      return certificate
    #else
      return nil
    #endif
  }

  func fetchCertificate(label: String) -> SecCertificate? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
      kSecAttrLabel as String: label,
      kSecReturnRef as String: true,
    ]
    addAccessGroup(to: &query)
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let ref = item {
      // swiftlint:disable:next force_cast
      return (ref as! SecCertificate)
    }
    return nil
  }

  func hasCertificate() -> Bool {
    return fetchCertificate(label: certLabel) != nil
  }

  func deleteAllCertificates() {
    var query: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
    ]
    addAccessGroup(to: &query)
    let status = SecItemDelete(query as CFDictionary)
    logger.info("deleteAllCertificates: status \(status, privacy: .public)")
  }

  // MARK: - Identity

  func loadIdentity() -> SecIdentity? {
    #if !targetEnvironment(simulator)
      var query: [String: Any] = [
        kSecClass as String: kSecClassIdentity,
        kSecAttrLabel as String: certLabel,
        kSecReturnRef as String: true,
      ]
      addAccessGroup(to: &query)

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      switch status {
      case errSecSuccess:
        // swiftlint:disable:next force_cast
        return (item as! SecIdentity)
      case errSecItemNotFound:
        logger.warning("loadIdentity: not found in keychain")
        return nil
      default:
        logger.warning("loadIdentity: SecItemCopyMatching failed, status \(status, privacy: .public)")
        return nil
      }
    #else
      return nil
    #endif
  }

  // MARK: - Cleanup

  func deleteAll() {
    deleteAllCertificates()
    deleteKeyPair()
  }

  // MARK: - Private

  private func addAccessGroup(to query: inout [String: Any]) {
    if let group = accessGroup {
      query[kSecAttrAccessGroup as String] = group
    }
  }

  private func getKeyPair() -> SecKeyPair? {
    #if !targetEnvironment(simulator)
      var query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: applicationTag,
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecReturnRef as String: true,
      ]
      addAccessGroup(to: &query)

      var existing: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &existing)
      lastKeyStatus = status
      if status == errSecSuccess, let existing = existing {
        // CF types: force cast is safe here as SecItemCopyMatching returns the requested type
        let privateKeyRef = existing as! SecKey
        guard let publicKey = SecKeyCopyPublicKey(privateKeyRef) else { return nil }
        return SecKeyPair(privateKey: privateKeyRef, publicKey: publicKey)
      }
      logger.info("getKeyPair: status \(status, privacy: .public) (\(self.describeStatus(status), privacy: .public))")
      return nil
    #else
      return nil
    #endif
  }

  private func createKeyPair() -> SecKeyPair? {
    #if !targetEnvironment(simulator)
      logger.info("createKeyPair: generating new RSA-2048 keypair")

      var privateKeyAttrs: [String: Any] = [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: applicationTag,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]
      addAccessGroup(to: &privateKeyAttrs)

      let params: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits as String: 2048,
        kSecPrivateKeyAttrs as String: privateKeyAttrs,
      ]

      var error: Unmanaged<CFError>?
      guard let privateKey = SecKeyCreateRandomKey(params as CFDictionary, &error) else {
        if let err = error?.takeRetainedValue() {
          logger.warning("createKeyPair: error: \(CFErrorCopyDescription(err), privacy: .public)")
          lastKeyStatus = OSStatus(CFErrorGetCode(err))
        }
        return nil
      }

      guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
        logger.warning("createKeyPair: failed to derive public key")
        return nil
      }

      return SecKeyPair(privateKey: privateKey, publicKey: publicKey)
    #else
      return nil
    #endif
  }

  var accessGroupDescription: String {
    return accessGroup ?? "nil (default)"
  }

  func lastKeyStatusDescription() -> String {
    if let status = lastKeyStatus {
      return "status \(status) (\(describeStatus(status)))"
    }
    return "no keypair; access group or entitlements may be missing"
  }

  private func describeStatus(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
      return message
    }
    return "unknown"
  }
}
