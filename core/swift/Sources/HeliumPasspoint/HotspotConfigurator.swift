#if os(iOS)

  import Foundation
  import NetworkExtension
  import os

  /// Wraps `NEHotspotConfigurationManager`, the iOS API that installs and
  /// removes Hotspot 2.0 (Passpoint) profiles.
  ///
  /// Requires the `com.apple.developer.networking.HotspotConfiguration`
  /// entitlement; without it every call fails at runtime.
  struct HotspotConfigurator {
    struct ProfileConfig {
      let domainName: String
      let naiRealmNames: [String]
      let trustedServerNames: [String]
      let tlsVersion: String
      let eapType: EAPType
      let identity: SecIdentity
    }

    private let logger = Logger(subsystem: "com.helium.passpoint", category: "HotspotConfigurator")

    func install(config: ProfileConfig) async throws {
      #if targetEnvironment(simulator)
        throw PasspointError.simulatorNotSupported
      #else
        let hs20Settings = NEHotspotHS20Settings(
          domainName: config.domainName, roamingEnabled: false)
        hs20Settings.naiRealmNames = config.naiRealmNames

        let eapSettings = NEHotspotEAPSettings()
        eapSettings.trustedServerNames = config.trustedServerNames
        eapSettings.isTLSClientCertificateRequired = true
        eapSettings.supportedEAPTypes = [NSNumber(value: config.eapType.rawValue)]
        eapSettings.preferredTLSVersion = Self.tlsVersion(config.tlsVersion)

        guard eapSettings.setIdentity(config.identity) else {
          throw PasspointError.identityLoadFailed
        }

        let hotspotConfig = NEHotspotConfiguration(
          hs20Settings: hs20Settings, eapSettings: eapSettings)
        hotspotConfig.hidden = false

        await removeAllProfiles()

        do {
          try await NEHotspotConfigurationManager.shared.apply(hotspotConfig)
        } catch {
          throw PasspointError.profileInstallFailed(error.localizedDescription)
        }
        logger.info("install: profile applied for \(config.domainName, privacy: .public)")
      #endif
    }

    func removeAllProfiles() async {
      #if !targetEnvironment(simulator)
        let domains = await configuredDomains()
        for domain in domains {
          NEHotspotConfigurationManager.shared.removeConfiguration(forHS20DomainName: domain)
        }
        logger.info("removeAllProfiles: removed \(domains.count, privacy: .public) profiles")
      #endif
    }

    func configuredDomains() async -> [String] {
      #if targetEnvironment(simulator)
        return []
      #else
        return await withCheckedContinuation { continuation in
          NEHotspotConfigurationManager.shared.getConfiguredSSIDs { ssids in
            continuation.resume(returning: ssids)
          }
        }
      #endif
    }

    /// See ``TLSVersionPreference`` for why an unrecognised value does not fail.
    static func tlsVersion(_ string: String) -> NEHotspotEAPSettings.TLSVersion {
      switch TLSVersionPreference.from(string) {
      case .v1_0: return NEHotspotEAPSettings.TLSVersion._1_0
      case .v1_1: return NEHotspotEAPSettings.TLSVersion._1_1
      case .v1_2: return NEHotspotEAPSettings.TLSVersion._1_2
      }
    }
  }

#endif
