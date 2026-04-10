import Foundation
import NetworkExtension
import os

class HotspotConfigurator {
  private let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  struct ProfileConfig {
    let domainName: String
    let naiRealmNames: [String]
    let trustedServerNames: [String]
    let tlsVersion: String
    let eapType: Int
    let identity: SecIdentity
  }

  func install(config: ProfileConfig) async throws {
    #if !targetEnvironment(simulator)
      let hs20Settings = NEHotspotHS20Settings(
        domainName: config.domainName, roamingEnabled: false)
      hs20Settings.naiRealmNames = config.naiRealmNames

      let eapSettings = NEHotspotEAPSettings()
      eapSettings.trustedServerNames = config.trustedServerNames
      eapSettings.isTLSClientCertificateRequired = true
      eapSettings.supportedEAPTypes = [NSNumber(value: config.eapType)]

      switch config.tlsVersion {
      case "1.0":
        eapSettings.preferredTLSVersion = NEHotspotEAPSettings.TLSVersion._1_0
      case "1.1":
        eapSettings.preferredTLSVersion = NEHotspotEAPSettings.TLSVersion._1_1
      case "1.2":
        eapSettings.preferredTLSVersion = NEHotspotEAPSettings.TLSVersion._1_2
      default:
        throw PasspointSDKError.profileInstallFailed(
          "Unsupported TLS version: \(config.tlsVersion)")
      }

      let identitySet = eapSettings.setIdentity(config.identity)
      logger.info("install: identity set: \(identitySet, privacy: .public)")
      guard identitySet else {
        throw PasspointSDKError.identityLoadFailed
      }

      let hotspotConfig = NEHotspotConfiguration(
        hs20Settings: hs20Settings, eapSettings: eapSettings)
      hotspotConfig.hidden = false

      // Remove existing configs before applying
      let existing = await getConfiguredDomains()
      for domain in existing {
        NEHotspotConfigurationManager.shared.removeConfiguration(forHS20DomainName: domain)
      }

      try await NEHotspotConfigurationManager.shared.apply(hotspotConfig)
      logger.info("install: profile applied successfully")
    #else
      throw PasspointSDKError.simulatorNotSupported
    #endif
  }

  func removeAllProfiles() async {
    #if !targetEnvironment(simulator)
      let domains = await getConfiguredDomains()
      for domain in domains {
        NEHotspotConfigurationManager.shared.removeConfiguration(forHS20DomainName: domain)
      }
      logger.info("removeAllProfiles: removed \(domains.count, privacy: .public) profiles")
    #endif
  }

  func hasInstalledProfile() async -> Bool {
    #if !targetEnvironment(simulator)
      let domains = await getConfiguredDomains()
      return !domains.isEmpty
    #else
      return false
    #endif
  }

  func getConfiguredDomains() async -> [String] {
    #if !targetEnvironment(simulator)
      return await withCheckedContinuation { continuation in
        NEHotspotConfigurationManager.shared.getConfiguredSSIDs { ssids in
          continuation.resume(returning: ssids)
        }
      }
    #else
      return []
    #endif
  }
}

// Internal error type used across the iOS SDK, mapped to PasspointErrorCode strings at the bridge.
enum PasspointSDKError: Error, LocalizedError {
  case notConfigured
  case simulatorNotSupported
  case csrGenerationFailed(String)
  case keypairGenerationFailed(String)
  case apiError(String)
  case apiUnauthorized
  case certificateParseFailed(String)
  case certificateSaveFailed(String)
  case identityLoadFailed
  case profileInstallFailed(String)
  case profileRemoveFailed(String)
  case certificateNotFound
  case removeFailed(String)
  case networkError(String)

  var errorCode: String {
    switch self {
    case .notConfigured: return "NOT_CONFIGURED"
    case .simulatorNotSupported: return "SIMULATOR_NOT_SUPPORTED"
    case .csrGenerationFailed: return "CSR_GENERATION_FAILED"
    case .keypairGenerationFailed: return "KEYPAIR_GENERATION_FAILED"
    case .apiError: return "API_ERROR"
    case .apiUnauthorized: return "API_UNAUTHORIZED"
    case .certificateParseFailed: return "CERTIFICATE_PARSE_FAILED"
    case .certificateSaveFailed: return "CERTIFICATE_SAVE_FAILED"
    case .identityLoadFailed: return "IDENTITY_LOAD_FAILED"
    case .profileInstallFailed: return "PROFILE_INSTALL_FAILED"
    case .profileRemoveFailed: return "PROFILE_REMOVE_FAILED"
    case .certificateNotFound: return "CERTIFICATE_NOT_FOUND"
    case .removeFailed: return "REMOVE_FAILED"
    case .networkError: return "NETWORK_ERROR"
    }
  }

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "SDK has not been configured. Call configure() first."
    case .simulatorNotSupported:
      return "Passpoint requires a physical device; simulators are not supported."
    case .csrGenerationFailed(let detail):
      return "Failed to generate CSR: \(detail)"
    case .keypairGenerationFailed(let detail):
      return "Failed to generate keypair: \(detail)"
    case .apiError(let detail):
      return "Passpoint API error: \(detail)"
    case .apiUnauthorized:
      return "API key was rejected (unauthorized)."
    case .certificateParseFailed(let detail):
      return "Failed to parse certificate: \(detail)"
    case .certificateSaveFailed(let detail):
      return "Failed to save certificate: \(detail)"
    case .identityLoadFailed:
      return "Failed to load TLS identity from keychain."
    case .profileInstallFailed(let detail):
      return "Failed to install Passpoint profile: \(detail)"
    case .profileRemoveFailed(let detail):
      return "Failed to remove Passpoint profile: \(detail)"
    case .certificateNotFound:
      return "No certificate is installed on this device."
    case .removeFailed(let detail):
      return "Certificate removal failed: \(detail)"
    case .networkError(let detail):
      return "Network error: \(detail)"
    }
  }
}
