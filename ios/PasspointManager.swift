import Foundation
import os

class PasspointManager {
  static let shared = PasspointManager()

  private let logger = Logger(subsystem: "com.helium.passpoint", category: "PasspointManager")
  private var apiKey: String?
  private var baseUrl: URL?
  private var eapType: Int = 13
  private var serverCaCertPem: String?
  private var presetId: String?

  private lazy var keychain = KeychainManager(logger: logger)
  private lazy var csrGenerator = CSRGenerator(logger: logger)
  private lazy var hotspot = HotspotConfigurator(logger: logger)

  private let certLabel = "HeliumPasspoint Cert"

  // Persisted profile metadata so getCertificateInfo() reports the
  // domain/friendly name actually used for the installed Passpoint profile,
  // not the inventory API host.
  private let defaults = UserDefaults.standard
  private let profileDomainKey = "com.helium.passpoint.profileDomain"
  private let profileFriendlyNameKey = "com.helium.passpoint.profileFriendlyName"

  private init() {}

  struct Profile: Decodable {
    let friendlyName: String
    let domainName: String
    let naiRealmNames: [String]
    let trustedServerNames: [String]
    let tlsVersion: String
    let certificate: String
    let caChain: [String]

    enum CodingKeys: String, CodingKey {
      case friendlyName = "friendly_name"
      case domainName = "domain_name"
      case naiRealmNames = "nai_realm_names"
      case trustedServerNames = "trusted_server_names"
      case tlsVersion = "tls_version"
      case certificate
      case caChain = "ca_chain"
    }
  }

  struct RemoteStatus: Decodable {
    let subscriberId: String
    let presetId: String
    let eapType: Int
    let expiresAt: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
      case subscriberId = "subscriber_id"
      case presetId = "preset_id"
      case eapType = "eap_type"
      case expiresAt = "expires_at"
      case active
    }
  }

  // MARK: - Configuration

  func configure(apiKey: String, baseUrl: String, eapType: Int, serverCaCertPem: String?, keychainAccessGroup: String? = nil, presetId: String? = nil) {
    self.apiKey = apiKey
    self.baseUrl = URL(string: baseUrl)
    self.eapType = eapType
    self.serverCaCertPem = serverCaCertPem
    self.presetId = presetId
    // Re-create keychain manager with the partner's access group
    self.keychain = KeychainManager(accessGroup: keychainAccessGroup, logger: logger)
    logger.info("configured: baseUrl=\(baseUrl, privacy: .public), eapType=\(eapType, privacy: .public)")
  }

  // MARK: - Install

  func install(subscriberId: String) async throws -> [String: Any] {
    guard let apiKey = apiKey, let baseUrl = baseUrl else {
      throw PasspointSDKError.notConfigured
    }

    #if targetEnvironment(simulator)
      throw PasspointSDKError.simulatorNotSupported
    #else
      // 0. Remove any existing profile so only one cert is installed at a time
      await hotspot.removeAllProfiles()
      keychain.deleteAll()

      // 1. Get or create keypair
      guard let keyPair = keychain.getOrCreateKeyPair() else {
        throw PasspointSDKError.keypairGenerationFailed(keychain.lastKeyStatusDescription())
      }

      // 2. Generate CSR
      guard let csr = csrGenerator.generate(
        subscriberId: subscriberId,
        keyPair: keyPair
      ) else {
        throw PasspointSDKError.csrGenerationFailed("CSR generation returned nil")
      }

      // 3. Call API
      let profile = try await fetchProfile(
        csr: csr,
        subscriberId: subscriberId,
        apiKey: apiKey,
        baseUrl: baseUrl
      )

      // 4. Clean previous certs
      keychain.deleteAllCertificates()

      // 5. Save root CA
      let rootCaPem = try loadServerCACert()
      guard keychain.saveCertificate(rootCaPem, label: "HeliumPasspoint Root CA") != nil else {
        throw PasspointSDKError.certificateSaveFailed("root CA")
      }

      // 6. Save CA chain
      for (idx, ca) in profile.caChain.enumerated() {
        guard keychain.saveCertificate(ca, label: "HeliumPasspoint CA Chain \(idx)") != nil else {
          throw PasspointSDKError.certificateSaveFailed("CA chain entry \(idx)")
        }
      }

      // 7. Save client cert
      guard keychain.saveCertificate(profile.certificate, label: certLabel) != nil else {
        throw PasspointSDKError.certificateSaveFailed("client certificate")
      }

      // 8. Load identity
      guard let identity = keychain.loadIdentity() else {
        throw PasspointSDKError.identityLoadFailed
      }

      // 9. Install hotspot profile
      try await hotspot.install(config: HotspotConfigurator.ProfileConfig(
        domainName: profile.domainName,
        naiRealmNames: profile.naiRealmNames,
        trustedServerNames: profile.trustedServerNames,
        tlsVersion: profile.tlsVersion,
        eapType: eapType,
        identity: identity
      ))

      // 10. Persist profile metadata for getCertificateInfo()
      defaults.set(profile.domainName, forKey: profileDomainKey)
      defaults.set(profile.friendlyName, forKey: profileFriendlyNameKey)
      logger.info("install: stored profile domain=\(profile.domainName, privacy: .public)")

      return ["success": true]
    #endif
  }

  // MARK: - isInstalled

  func isInstalled() async -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      // On iOS 26+, getConfiguredSSIDs no longer returns HS2.0 domains.
      // Use the keychain certificate as the source of truth — it's saved during
      // install and cleared during remove.
      return keychain.hasCertificate()
    #endif
  }

  // MARK: - getCertificateInfo

  func getCertificateInfo() async -> [String: Any?] {
    #if targetEnvironment(simulator)
      return notInstalledInfo()
    #else
      guard let cert = keychain.fetchCertificate(label: certLabel) else {
        return notInstalledInfo()
      }

      let subject = CertificateStore.subjectSummary(of: cert)
      var isoExpiry: String? = nil
      if let expiry = CertificateStore.expirationDate(of: cert) {
        isoExpiry = ISO8601DateFormatter().string(from: expiry)
      }

      return [
        "isInstalled": true,
        "expiresAt": isoExpiry as Any?,
        "subject": subject as Any?,
        "domain": defaults.string(forKey: profileDomainKey) as Any?,
        "friendlyName": defaults.string(forKey: profileFriendlyNameKey) as Any?,
      ]
    #endif
  }

  // MARK: - getRemoteStatus

  func getRemoteStatus(subscriberId: String) async throws -> [String: Any]? {
    guard let apiKey = apiKey, let baseUrl = baseUrl else {
      throw PasspointSDKError.notConfigured
    }

    var components = URLComponents(url: baseUrl.appendingPathComponent("preset/profile/status"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "subscriber_id", value: subscriberId)]
    guard let url = components?.url else {
      throw PasspointSDKError.apiError("Failed to construct status URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(apiKey, forHTTPHeaderField: "X-Helium-P-Api-Key")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw PasspointSDKError.networkError(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw PasspointSDKError.apiError("Invalid response")
    }

    switch http.statusCode {
    case 200...299:
      let status: RemoteStatus
      do {
        status = try JSONDecoder().decode(RemoteStatus.self, from: data)
      } catch {
        throw PasspointSDKError.apiError("Failed to decode status: \(error.localizedDescription)")
      }
      return [
        "subscriberId": status.subscriberId,
        "presetId": status.presetId,
        "eapType": status.eapType,
        "expiresAt": status.expiresAt,
        "active": status.active,
      ]
    case 404:
      return nil
    case 401, 403:
      throw PasspointSDKError.apiUnauthorized
    default:
      let body = String(data: data, encoding: .utf8) ?? ""
      throw PasspointSDKError.apiError("HTTP \(http.statusCode): \(body)")
    }
  }

  // MARK: - Remove

  func remove() async throws -> [String: Any] {
    guard apiKey != nil else {
      throw PasspointSDKError.notConfigured
    }

    #if targetEnvironment(simulator)
      throw PasspointSDKError.simulatorNotSupported
    #else
      await hotspot.removeAllProfiles()
      keychain.deleteAll()
      defaults.removeObject(forKey: profileDomainKey)
      defaults.removeObject(forKey: profileFriendlyNameKey)

      return ["success": true]
    #endif
  }

  // MARK: - Debug

  func debug() async -> [String: Any] {
    var info: [String: Any] = [
      "configured": apiKey != nil,
      "baseUrl": baseUrl?.absoluteString ?? "nil",
      "eapType": eapType,
      "presetId": presetId ?? "nil",
      "keychainAccessGroup": keychain.accessGroupDescription,
    ]

    #if targetEnvironment(simulator)
      info["platform"] = "simulator"
    #else
      info["platform"] = "device"

      // Check keychain cert
      let hasCert = keychain.hasCertificate()
      info["hasCert"] = hasCert

      // Check keychain keypair
      let hasKeyPair = keychain.getOrCreateKeyPair() != nil
      info["hasKeyPair"] = hasKeyPair

      // Check configured SSIDs
      let domains = await hotspot.getConfiguredDomains()
      info["configuredSSIDs"] = domains
      info["hasProfile"] = !domains.isEmpty

      // Keychain cert label
      info["certLabel"] = certLabel

      // Try fetching the cert directly
      if let cert = keychain.fetchCertificate(label: certLabel) {
        info["certFound"] = true
        info["certSubject"] = CertificateStore.subjectSummary(of: cert) ?? "nil"
      } else {
        info["certFound"] = false
      }
    #endif

    return info
  }

  // MARK: - Private

  private func notInstalledInfo() -> [String: Any?] {
    return [
      "isInstalled": false,
      "expiresAt": nil,
      "subject": nil,
      "domain": nil,
      "friendlyName": nil,
    ]
  }

  private func loadServerCACert() throws -> String {
    // Prefer custom PEM if provided at configure time
    if let custom = serverCaCertPem, !custom.isEmpty {
      return custom
    }

    // Load from SDK bundle
    let sdkBundle = Bundle(for: PasspointManager.self)
    // resource_bundles in podspec creates a nested bundle
    if let resourceBundleURL = sdkBundle.url(
      forResource: "HeliumPasspointSDK", withExtension: "bundle"),
      let resourceBundle = Bundle(url: resourceBundleURL),
      let url = resourceBundle.url(forResource: "serverCA", withExtension: "crt"),
      let contents = try? String(contentsOf: url)
    {
      return contents
    }
    // Fallback: check the main bundle (for development / example app)
    if let url = Bundle.main.url(forResource: "serverCA", withExtension: "crt"),
      let contents = try? String(contentsOf: url)
    {
      return contents
    }
    throw PasspointSDKError.certificateParseFailed("serverCA.crt not found in any bundle")
  }

  private func fetchProfile(csr: String, subscriberId: String, apiKey: String, baseUrl: URL) async throws -> Profile {
    logger.info("fetchProfile: sending CSR to API")

    let url = baseUrl.appendingPathComponent("preset/profile/generate")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "X-Helium-P-Api-Key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "type": eapType,
      "subscriber_id": subscriberId,
      "csr": csr,
    ]
    if let presetId = presetId, !presetId.isEmpty {
      body["preset_id"] = presetId
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw PasspointSDKError.networkError(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw PasspointSDKError.apiError("Invalid response")
    }

    switch http.statusCode {
    case 200...299:
      break
    case 401, 403:
      throw PasspointSDKError.apiUnauthorized
    default:
      let body = String(data: data, encoding: .utf8) ?? ""
      throw PasspointSDKError.apiError("HTTP \(http.statusCode): \(body)")
    }

    do {
      return try JSONDecoder().decode(Profile.self, from: data)
    } catch {
      throw PasspointSDKError.apiError("Failed to decode profile: \(error.localizedDescription)")
    }
  }
}
