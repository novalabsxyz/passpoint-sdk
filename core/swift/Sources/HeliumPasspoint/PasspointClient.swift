#if os(iOS)

  import Foundation
  import os

  /// Entry point to the Helium Passpoint SDK.
  ///
  /// ```swift
  /// let client = PasspointClient.shared
  /// try client.configure(PasspointConfig(
  ///   apiKey: "…",
  ///   keychainAccessGroup: "TEAMID.com.apple.networkextensionsharing"
  /// ))
  /// try await client.install(subscriberID: "subscriber-123")
  /// ```
  ///
  /// The app must carry the **Hotspot Configuration** entitlement and share the
  /// NetworkExtension keychain group, or ``install(subscriberID:)`` will fail —
  /// see the SDK README for the Xcode setup.
  ///
  /// Passpoint is unavailable on the simulator; ``install(subscriberID:)`` and
  /// ``remove()`` throw ``PasspointErrorCode/simulatorNotSupported`` there.
  ///
  /// **Thread safety.** Safe to call from anywhere, including concurrently.
  /// ``install(subscriberID:)`` and ``remove()`` are serialised against each
  /// other so a half-provisioned device cannot result; the read-only queries
  /// are not gated and stay responsive while an install is running.
  public final class PasspointClient: @unchecked Sendable {
    /// Shared instance, matching the singleton the React Native bridge uses.
    /// Apps that prefer their own lifetime can use ``init()`` instead.
    public static let shared = PasspointClient()

    private let logger = Logger(subsystem: "com.helium.passpoint", category: "PasspointClient")
    private let defaults: UserDefaults
    private let hotspot = HotspotConfigurator()

    /// Guards ``config`` and ``keychain``. `@unchecked Sendable` above is
    /// justified by this lock plus the fact that every other stored property is
    /// immutable.
    private let stateLock = NSLock()
    private var _config: PasspointConfig?
    private var _keychain = KeychainManager()

    /// Serialises the destructive operations.
    private let gate = SerialGate()

    private let certLabel = KeychainManager.defaultCertificateLabel
    private static let profileDomainKey = "com.helium.passpoint.profileDomain"
    private static let profileFriendlyNameKey = "com.helium.passpoint.profileFriendlyName"

    public init(defaults: UserDefaults = .standard) {
      self.defaults = defaults
    }

    private var config: PasspointConfig? {
      stateLock.lock()
      defer { stateLock.unlock() }
      return _config
    }

    private var keychain: KeychainManager {
      stateLock.lock()
      defer { stateLock.unlock() }
      return _keychain
    }

    // MARK: - Configuration

    /// Store the SDK configuration. Must be called before anything else.
    ///
    /// Calling this while an install is in flight is not meaningful — the
    /// operation already captured the configuration it started with.
    ///
    /// - Throws: ``PasspointError`` with code `INVALID_CONFIG` if `apiKey` is blank.
    public func configure(_ config: PasspointConfig) throws {
      let validated = try config.validated()

      stateLock.lock()
      _config = validated
      _keychain = KeychainManager(
        certLabel: certLabel, accessGroup: validated.keychainAccessGroup)
      stateLock.unlock()

      logger.info(
        "configured: baseURL=\(validated.environment.baseURL.absoluteString, privacy: .public), eapType=\(validated.eapType.rawValue, privacy: .public)"
      )
    }

    /// Whether ``configure(_:)`` has been called successfully.
    public var isConfigured: Bool { config != nil }

    // MARK: - Install

    /// Provision a Passpoint profile for `subscriberID`.
    ///
    /// Generates an RSA-2048 keypair, sends a CSR to the Helium inventory API,
    /// stores the issued certificate chain in the keychain, and installs the
    /// Hotspot 2.0 profile. Any profile previously installed by this SDK is
    /// removed first, so a device only ever holds one Helium credential.
    ///
    /// - Parameter subscriberID: Partner-defined subscriber identifier. Opaque
    ///   to the SDK; the server revokes any prior certificate issued for it.
    public func install(subscriberID: String) async throws {
      let config = try requireConfig()

      guard !subscriberID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw PasspointError.invalidConfig("subscriberID is required and must be non-empty.")
      }

      try await gate.run { try await self.performInstall(subscriberID: subscriberID, config: config) }
    }

    private func performInstall(subscriberID: String, config: PasspointConfig) async throws {
      #if targetEnvironment(simulator)
        throw PasspointError.simulatorNotSupported
      #else
        // Only one Helium credential may exist at a time.
        await hotspot.removeAllProfiles()
        keychain.deleteAll()

        guard let keyPair = keychain.getOrCreateKeyPair() else {
          throw PasspointError.keypairGenerationFailed(keychain.lastKeyStatusDescription())
        }

        let csr = try CSRGenerator().generate(subscriberID: subscriberID, keyPair: keyPair)

        let profile = try await apiClient(for: config).generateProfile(
          csr: csr,
          subscriberID: subscriberID,
          eapType: config.eapType,
          presetID: config.presetID
        )

        // isInstalled() is derived from the keychain certificate, so anything
        // that fails after the certificate lands would leave the device
        // reporting "installed" with no working profile. Roll back instead.
        do {
          let rootCAPEM = try config.serverCACertificatePEM.flatMap { $0.isEmpty ? nil : $0 }
            ?? ServerCA.bundledPEM()
          guard keychain.saveCertificate(rootCAPEM, label: KeychainManager.rootCALabel) != nil
          else {
            throw PasspointError.certificateSaveFailed("root CA")
          }

          for (index, ca) in profile.caChain.enumerated() {
            guard
              keychain.saveCertificate(ca, label: KeychainManager.caChainLabel(index: index)) != nil
            else {
              throw PasspointError.certificateSaveFailed("CA chain entry \(index)")
            }
          }

          guard keychain.saveCertificate(profile.certificate, label: certLabel) != nil else {
            throw PasspointError.certificateSaveFailed("client certificate")
          }

          guard let identity = keychain.loadIdentity() else {
            throw PasspointError.identityLoadFailed
          }

          try await hotspot.install(
            config: HotspotConfigurator.ProfileConfig(
              domainName: profile.domainName,
              naiRealmNames: profile.naiRealmNames,
              trustedServerNames: profile.trustedServerNames,
              tlsVersion: profile.tlsVersion,
              eapType: config.eapType,
              identity: identity
            ))
        } catch {
          await hotspot.removeAllProfiles()
          keychain.deleteAll()
          defaults.removeObject(forKey: Self.profileDomainKey)
          defaults.removeObject(forKey: Self.profileFriendlyNameKey)
          logger.warning("install: rolled back after failure")
          throw error
        }

        // Remembered so certificateInfo() can report the profile's own domain
        // and name rather than the inventory API host.
        defaults.set(profile.domainName, forKey: Self.profileDomainKey)
        defaults.set(profile.friendlyName, forKey: Self.profileFriendlyNameKey)
        logger.info("install: stored profile domain=\(profile.domainName, privacy: .public)")
      #endif
    }

    // MARK: - Queries

    /// Whether a Helium Passpoint credential is installed on this device.
    ///
    /// From iOS 26 `getConfiguredSSIDs` no longer reports HS2.0 domains, so the
    /// keychain certificate — written on install, cleared on remove — is the
    /// source of truth.
    public func isInstalled() async -> Bool {
      #if targetEnvironment(simulator)
        return false
      #else
        return keychain.hasCertificate()
      #endif
    }

    /// Details of the installed credential. Returns
    /// ``CertificateInfo/notInstalled`` rather than throwing when there is none.
    public func certificateInfo() async -> CertificateInfo {
      #if targetEnvironment(simulator)
        return .notInstalled
      #else
        guard let certificate = keychain.fetchCertificate(label: certLabel) else {
          return .notInstalled
        }
        return CertificateInfo(
          isInstalled: true,
          expiresAt: CertificateStore.expirationDate(of: certificate),
          subject: CertificateStore.subjectSummary(of: certificate),
          domain: defaults.string(forKey: Self.profileDomainKey),
          friendlyName: defaults.string(forKey: Self.profileFriendlyNameKey)
        )
      #endif
    }

    /// The server's view of a subscriber's profile.
    ///
    /// Unlike ``isInstalled()`` this hits the network, so it detects
    /// server-side revocation and confirms an install landed end to end.
    ///
    /// - Returns: `nil` when the server has no profile for `subscriberID`.
    public func remoteStatus(subscriberID: String) async throws -> RemoteProfileStatus? {
      let config = try requireConfig()

      guard !subscriberID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw PasspointError.invalidConfig("subscriberID is required and must be non-empty.")
      }
      return try await apiClient(for: config).profileStatus(subscriberID: subscriberID)
    }

    // MARK: - Remove

    /// Remove the Passpoint profile and delete every keychain item the SDK owns.
    public func remove() async throws {
      _ = try requireConfig()
      try await gate.run { try await self.performRemove() }
    }

    private func performRemove() async throws {
      #if targetEnvironment(simulator)
        throw PasspointError.simulatorNotSupported
      #else
        await hotspot.removeAllProfiles()
        keychain.deleteAll()
        defaults.removeObject(forKey: Self.profileDomainKey)
        defaults.removeObject(forKey: Self.profileFriendlyNameKey)
      #endif
    }

    // MARK: - Diagnostics

    /// Support-facing snapshot of SDK state. Never contains the API key.
    /// The shape is not part of the SDK's compatibility promise.
    public func diagnostics() async -> [String: String] {
      var info: [String: String] = [
        "configured": String(config != nil),
        "baseUrl": config?.environment.baseURL.absoluteString ?? "nil",
        "eapType": config.map { String($0.eapType.rawValue) } ?? "nil",
        "presetId": config?.presetID ?? "nil",
        "keychainAccessGroup": keychain.accessGroupDescription,
        "certLabel": certLabel,
        "profileDomain": defaults.string(forKey: Self.profileDomainKey) ?? "nil",
        "profileFriendlyName": defaults.string(forKey: Self.profileFriendlyNameKey) ?? "nil",
      ]

      #if targetEnvironment(simulator)
        info["platform"] = "simulator"
      #else
        info["platform"] = "device"
        info["hasCert"] = String(keychain.hasCertificate())
        info["hasKeyPair"] = String(keychain.hasKeyPair())

        let domains = await hotspot.configuredDomains()
        info["configuredSSIDs"] = domains.joined(separator: ",")
        info["hasProfile"] = String(!domains.isEmpty)

        if let certificate = keychain.fetchCertificate(label: certLabel) {
          info["certFound"] = "true"
          info["certSubject"] = CertificateStore.subjectSummary(of: certificate) ?? "nil"
        } else {
          info["certFound"] = "false"
        }
      #endif

      return info
    }

    // MARK: - Private

    private func requireConfig() throws -> PasspointConfig {
      guard let config else { throw PasspointError.notConfigured }
      return config
    }

    private func apiClient(for config: PasspointConfig) -> ProfileAPIClient {
      ProfileAPIClient(baseURL: config.environment.baseURL, apiKey: config.apiKey)
    }
  }

  /// Runs submitted operations one at a time, in submission order.
  ///
  /// An `actor` alone would not do: actors protect state but are reentrant
  /// across `await`, so two installs could still interleave at a suspension
  /// point — one deleting the keychain items the other just wrote. Chaining the
  /// tasks makes each operation wait for the previous one to finish.
  private actor SerialGate {
    private var last: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
      let previous = last
      let task = Task<T, Error> {
        await previous?.value
        return try await operation()
      }
      // Erased so a thrown error does not break the chain for later callers.
      last = Task { _ = try? await task.value }
      return try await task.value
    }
  }

#endif
