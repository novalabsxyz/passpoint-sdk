import Foundation

/// Machine-readable error codes shared by the Swift, Kotlin and TypeScript SDKs.
///
/// The full set is defined in `core/contract/contract.json` and asserted by
/// `ContractConformanceTests`. Some codes are only ever emitted on one platform
/// (`SIMULATOR_NOT_SUPPORTED` is iOS-only, `WIFI_MANAGER_UNAVAILABLE` is
/// Android-only) but every SDK declares the complete set so partners can write
/// one `switch` that compiles everywhere.
public enum PasspointErrorCode: String, CaseIterable, Sendable {
  // Configuration
  case notConfigured = "NOT_CONFIGURED"
  case invalidAPIKey = "INVALID_API_KEY"
  case invalidConfig = "INVALID_CONFIG"

  // Platform
  case platformNotSupported = "PLATFORM_NOT_SUPPORTED"
  case simulatorNotSupported = "SIMULATOR_NOT_SUPPORTED"
  case missingEntitlements = "MISSING_ENTITLEMENTS"
  case permissionDenied = "PERMISSION_DENIED"

  // Keypair / CSR
  case keypairGenerationFailed = "KEYPAIR_GENERATION_FAILED"
  case csrGenerationFailed = "CSR_GENERATION_FAILED"

  // Network / API
  case networkError = "NETWORK_ERROR"
  case apiError = "API_ERROR"
  case apiUnauthorized = "API_UNAUTHORIZED"
  case apiRateLimited = "API_RATE_LIMITED"

  // Certificate
  case certificateParseFailed = "CERTIFICATE_PARSE_FAILED"
  case certificateSaveFailed = "CERTIFICATE_SAVE_FAILED"
  case certificateNotFound = "CERTIFICATE_NOT_FOUND"
  case identityLoadFailed = "IDENTITY_LOAD_FAILED"

  // Profile
  case profileInstallFailed = "PROFILE_INSTALL_FAILED"
  case profileInstallCancelled = "PROFILE_INSTALL_CANCELLED"
  case profileNotFound = "PROFILE_NOT_FOUND"
  case profileRemoveFailed = "PROFILE_REMOVE_FAILED"

  // Removal
  case removeFailed = "REMOVE_FAILED"

  // Android-specific (declared for parity; never thrown on iOS)
  case wifiManagerUnavailable = "WIFI_MANAGER_UNAVAILABLE"
  case networkSuggestionDisallowed = "NETWORK_SUGGESTION_DISALLOWED"
  case networkSuggestionLimit = "NETWORK_SUGGESTION_LIMIT"

  // Generic
  case unknown = "UNKNOWN"
}

/// The only error type thrown by the Helium Passpoint SDK.
///
/// Switch on ``code`` to handle specific failures:
///
/// ```swift
/// do {
///   try await client.install(subscriberID: "sub-123")
/// } catch let error as PasspointError {
///   switch error.code {
///   case .simulatorNotSupported: print("run on a device")
///   case .apiUnauthorized:       print("bad API key")
///   default:                     print(error.localizedDescription)
///   }
/// }
/// ```
public struct PasspointError: Error, LocalizedError, Equatable, Sendable {
  /// Machine-readable code, stable across SDK versions and platforms.
  public let code: PasspointErrorCode

  /// Human-readable detail. Not localized; safe to log, never contains the API key.
  public let message: String

  public init(code: PasspointErrorCode, message: String) {
    self.code = code
    self.message = message
  }

  public var errorDescription: String? { message }

  // MARK: - Factories

  static var notConfigured: PasspointError {
    PasspointError(
      code: .notConfigured,
      message: "SDK has not been configured. Call configure(_:) first.")
  }

  static var simulatorNotSupported: PasspointError {
    PasspointError(
      code: .simulatorNotSupported,
      message: "Passpoint requires a physical device; simulators are not supported.")
  }

  static var apiUnauthorized: PasspointError {
    PasspointError(code: .apiUnauthorized, message: "API key was rejected (unauthorized).")
  }

  static var identityLoadFailed: PasspointError {
    PasspointError(
      code: .identityLoadFailed, message: "Failed to load TLS identity from keychain.")
  }

  static func csrGenerationFailed(_ detail: String) -> PasspointError {
    PasspointError(code: .csrGenerationFailed, message: "Failed to generate CSR: \(detail)")
  }

  static func keypairGenerationFailed(_ detail: String) -> PasspointError {
    PasspointError(
      code: .keypairGenerationFailed, message: "Failed to generate keypair: \(detail)")
  }

  static func apiError(_ detail: String) -> PasspointError {
    PasspointError(code: .apiError, message: "Passpoint API error: \(detail)")
  }

  static func apiRateLimited(_ detail: String) -> PasspointError {
    PasspointError(code: .apiRateLimited, message: "Passpoint API rate limit exceeded: \(detail)")
  }

  static func networkError(_ detail: String) -> PasspointError {
    PasspointError(code: .networkError, message: "Network error: \(detail)")
  }

  static func certificateParseFailed(_ detail: String) -> PasspointError {
    PasspointError(
      code: .certificateParseFailed, message: "Failed to parse certificate: \(detail)")
  }

  static func certificateSaveFailed(_ detail: String) -> PasspointError {
    PasspointError(code: .certificateSaveFailed, message: "Failed to save certificate: \(detail)")
  }

  static func profileInstallFailed(_ detail: String) -> PasspointError {
    PasspointError(
      code: .profileInstallFailed, message: "Failed to install Passpoint profile: \(detail)")
  }

  static func invalidConfig(_ detail: String) -> PasspointError {
    PasspointError(code: .invalidConfig, message: "Invalid configuration: \(detail)")
  }
}
