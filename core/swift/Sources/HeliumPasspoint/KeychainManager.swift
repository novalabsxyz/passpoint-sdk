import Foundation
import Security
import os

/// Owns every keychain item the SDK creates: the RSA keypair, the issued client
/// certificate, and the CA chain needed to build a `SecIdentity`.
///
/// Every item the SDK writes carries a label beginning with ``labelPrefix``,
/// and deletion only ever touches those. This matters because the access group
/// the SDK must use — `<TEAM_ID>.com.apple.networkextensionsharing` — is shared
/// with the app's other NetworkExtension components: a class-wide delete would
/// take their certificates with it.
final class KeychainManager {
  /// Every certificate the SDK stores is labelled with this prefix.
  static let labelPrefix = "HeliumPasspoint"
  static let defaultCertificateLabel = "HeliumPasspoint Cert"
  static let rootCALabel = "HeliumPasspoint Root CA"

  static func caChainLabel(index: Int) -> String { "\(labelPrefix) CA Chain \(index)" }

  private let applicationTag: Data
  private let certLabel: String
  private let accessGroup: String?
  private let logger = Logger(subsystem: "com.helium.passpoint", category: "KeychainManager")
  private var lastKeyStatus: OSStatus?

  init(
    applicationTag: String = "com.helium.passpoint.rsa-key",
    certLabel: String = KeychainManager.defaultCertificateLabel,
    accessGroup: String? = nil
  ) {
    self.applicationTag = Data(applicationTag.utf8)
    self.certLabel = certLabel
    self.accessGroup = accessGroup
  }

  var accessGroupDescription: String { accessGroup ?? "nil (default)" }

  // MARK: - Keypair

  static let keySizeBits = 2048

  func getOrCreateKeyPair() -> SecKeyPair? {
    getKeyPair() ?? createKeyPair()
  }

  /// Read-only probe for diagnostics. Unlike ``getOrCreateKeyPair()`` this
  /// never generates a key, so calling it does not mutate device state.
  func hasKeyPair() -> Bool {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: applicationTag,
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
    ]
    addAccessGroup(to: &query)
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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

  @discardableResult
  func saveCertificate(_ pem: String, label: String) -> SecCertificate? {
    guard let certificate = CertificateStore.parsePEM(pem) else {
      logger.warning("saveCertificate: could not parse \(label, privacy: .public)")
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
      logger.info("saveCertificate: duplicate \(label, privacy: .public), reusing existing")
      return fetchCertificate(label: label) ?? certificate
    }
    if status != errSecSuccess {
      // Deliberately non-fatal. Some devices report a failure here yet still
      // hold the item (and some entitlement misconfigurations surface later, as
      // IDENTITY_LOAD_FAILED, which is the more actionable error). Returning nil
      // would abort install at the root-CA step and lose that signal.
      logger.warning(
        "saveCertificate: SecItemAdd status \(status, privacy: .public) for \(label, privacy: .public)"
      )
    }
    return certificate
  }

  func fetchCertificate(label: String) -> SecCertificate? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
      kSecAttrLabel as String: label,
      kSecReturnRef as String: true,
    ]
    addAccessGroup(to: &query)

    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let result = item
    else { return nil }
    // SecItemCopyMatching with kSecClassCertificate + kSecReturnRef always
    // yields a SecCertificate.
    return (result as! SecCertificate)  // swiftlint:disable:this force_cast
  }

  func hasCertificate() -> Bool {
    fetchCertificate(label: certLabel) != nil
  }

  /// Delete only the certificates this SDK wrote.
  ///
  /// Never issue a class-wide `SecItemDelete` here: with the shared
  /// NetworkExtension access group that would delete certificates belonging to
  /// the rest of the app.
  func deleteSDKCertificates() {
    var labels = sdkCertificateLabels()
    // The configured client-certificate label may have been overridden to
    // something outside the prefix.
    labels.insert(certLabel)

    for label in labels.sorted() {
      var query: [String: Any] = [
        kSecClass as String: kSecClassCertificate,
        kSecAttrLabel as String: label,
      ]
      addAccessGroup(to: &query)
      let status = SecItemDelete(query as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound {
        logger.warning(
          "deleteSDKCertificates: status \(status, privacy: .public) for \(label, privacy: .public)"
        )
      }
    }
    logger.info("deleteSDKCertificates: removed \(labels.count, privacy: .public) labels")
  }

  /// Labels of every certificate in the access group that this SDK owns.
  func sdkCertificateLabels() -> Set<String> {
    var query: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnAttributes as String: true,
    ]
    addAccessGroup(to: &query)

    var items: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
      let attributes = items as? [[String: Any]]
    else { return [] }

    return Set(
      attributes
        .compactMap { $0[kSecAttrLabel as String] as? String }
        .filter { $0.hasPrefix(Self.labelPrefix) }
    )
  }

  // MARK: - Identity

  func loadIdentity() -> SecIdentity? {
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
      guard let result = item else { return nil }
      return (result as! SecIdentity)  // swiftlint:disable:this force_cast
    case errSecItemNotFound:
      logger.warning("loadIdentity: not found in keychain")
      return nil
    default:
      logger.warning("loadIdentity: status \(status, privacy: .public)")
      return nil
    }
  }

  // MARK: - Cleanup

  func deleteAll() {
    deleteSDKCertificates()
    deleteKeyPair()
  }

  func lastKeyStatusDescription() -> String {
    guard let status = lastKeyStatus else {
      return "no keypair; access group or entitlements may be missing"
    }
    return "status \(status) (\(Self.describe(status)))"
  }

  // MARK: - Private

  private func addAccessGroup(to query: inout [String: Any]) {
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
  }

  private func getKeyPair() -> SecKeyPair? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: applicationTag,
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
      kSecReturnRef as String: true,
    ]
    addAccessGroup(to: &query)

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    lastKeyStatus = status
    guard status == errSecSuccess, let result = item else {
      logger.info(
        "getKeyPair: status \(status, privacy: .public) (\(Self.describe(status), privacy: .public))"
      )
      return nil
    }
    let privateKey = result as! SecKey  // swiftlint:disable:this force_cast
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
    return SecKeyPair(privateKey: privateKey, publicKey: publicKey)
  }

  private func createKeyPair() -> SecKeyPair? {
    logger.info("createKeyPair: generating RSA-\(Self.keySizeBits, privacy: .public)")

    var privateKeyAttrs: [String: Any] = [
      kSecAttrIsPermanent as String: true,
      kSecAttrApplicationTag as String: applicationTag,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    addAccessGroup(to: &privateKeyAttrs)

    let params: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits as String: Self.keySizeBits,
      kSecPrivateKeyAttrs as String: privateKeyAttrs,
    ]

    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(params as CFDictionary, &error) else {
      if let err = error?.takeRetainedValue() {
        logger.warning("createKeyPair: \(CFErrorCopyDescription(err), privacy: .public)")
        lastKeyStatus = OSStatus(CFErrorGetCode(err))
      }
      return nil
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      logger.warning("createKeyPair: could not derive public key")
      return nil
    }
    return SecKeyPair(privateKey: privateKey, publicKey: publicKey)
  }

  private static func describe(_ status: OSStatus) -> String {
    SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
  }
}
