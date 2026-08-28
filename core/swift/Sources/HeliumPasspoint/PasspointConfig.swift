import Foundation

/// EAP authentication types supported by the SDK (IANA EAP method numbers).
public enum EAPType: Int, CaseIterable, Sendable {
  /// EAP-TLS (certificate-based). The default and the only type Helium provisions today.
  case tls = 13
  /// EAP-TTLS (tunneled TLS).
  case ttls = 21
  /// EAP-PEAP (Protected EAP).
  case peap = 25
}

/// A Helium inventory API deployment.
///
/// Use ``custom(_:)`` to point at a private deployment; the URL must end at the
/// API root (`.../api/inventory/v1`) with no trailing path or slash.
public enum PasspointEnvironment: Equatable, Sendable {
  case production
  case development
  case poc
  case custom(URL)

  /// Base URL of the inventory API for this environment.
  public var baseURL: URL {
    switch self {
    case .production:
      return URL(string: "https://api.prod.hib.nova.xyz/api/inventory/v1")!
    case .development:
      return URL(string: "https://api-dev.dev.hib.nova.xyz/api/inventory/v1")!
    case .poc:
      return URL(string: "https://api.dev.hib.nova.xyz/api/inventory/v1")!
    case .custom(let url):
      return PasspointEnvironment.trimmingTrailingSlashes(url)
    }
  }

  /// Resolve an environment from its string name, matching the TypeScript SDK's
  /// `environment` config option. A value starting with `http` is treated as a
  /// custom base URL. Unknown names fall back to ``production``.
  public static func named(_ name: String) -> PasspointEnvironment {
    if name.hasPrefix("http") {
      guard let url = URL(string: name) else { return .production }
      return .custom(url)
    }
    switch name {
    case "production": return .production
    case "development": return .development
    case "poc": return .poc
    default: return .production
    }
  }

  private static func trimmingTrailingSlashes(_ url: URL) -> URL {
    var string = url.absoluteString
    while string.hasSuffix("/") { string.removeLast() }
    return URL(string: string) ?? url
  }
}

/// The TLS version the profile asks the OS to prefer.
///
/// Platform-independent so the mapping is unit-testable; iOS turns it into an
/// `NEHotspotEAPSettings.TLSVersion`, which tops out at 1.2.
enum TLSVersionPreference: String, CaseIterable {
  case v1_0 = "1.0"
  case v1_1 = "1.1"
  case v1_2 = "1.2"

  /// `preferredTLSVersion` is a *preference* — the OS still negotiates upward —
  /// so an unrecognised value falls back to 1.2 rather than failing the
  /// install. The day the inventory API emits `"1.3"`, iOS keeps working, as
  /// Android already does (it ignores the field entirely).
  static func from(_ string: String) -> TLSVersionPreference {
    TLSVersionPreference(rawValue: string) ?? .v1_2
  }
}

/// Configuration for ``PasspointClient``.
///
/// ```swift
/// let client = PasspointClient()
/// try client.configure(PasspointConfig(
///   apiKey: "…",
///   keychainAccessGroup: "TEAMID.com.apple.networkextensionsharing"
/// ))
/// ```
public struct PasspointConfig: Equatable, Sendable {
  /// Partner API key issued by Helium.
  public var apiKey: String

  /// API deployment to talk to. Defaults to ``PasspointEnvironment/production``.
  public var environment: PasspointEnvironment

  /// EAP authentication type. Defaults to ``EAPType/tls``; most partners should not change it.
  public var eapType: EAPType

  /// Custom server CA certificate in PEM form. When `nil`, the CA bundled with
  /// the SDK is used.
  public var serverCACertificatePEM: String?

  /// Keychain access group used for the client identity. Must be listed in the
  /// app's Keychain Sharing entitlement, and must be the NetworkExtension
  /// sharing group for Passpoint installation to succeed:
  /// `<TEAM_ID>.com.apple.networkextensionsharing`.
  ///
  /// When `nil` the SDK does not set an access group, which will normally make
  /// ``PasspointClient/install(subscriberID:)`` fail at profile installation.
  public var keychainAccessGroup: String?

  /// Preset UUID. Required only when the partner account has more than one
  /// EAP-TLS preset configured.
  public var presetID: String?

  public init(
    apiKey: String,
    environment: PasspointEnvironment = .production,
    eapType: EAPType = .tls,
    serverCACertificatePEM: String? = nil,
    keychainAccessGroup: String? = nil,
    presetID: String? = nil
  ) {
    self.apiKey = apiKey
    self.environment = environment
    self.eapType = eapType
    self.serverCACertificatePEM = serverCACertificatePEM
    self.keychainAccessGroup = keychainAccessGroup
    self.presetID = presetID
  }

  /// Throws ``PasspointError`` with code `INVALID_CONFIG` when the config cannot be used.
  func validated() throws -> PasspointConfig {
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PasspointError.invalidConfig("apiKey is required and must be non-empty.")
    }
    return self
  }
}

extension PasspointConfig: CustomStringConvertible, CustomDebugStringConvertible {
  /// Redacts the API key. The synthesised description of a struct prints every
  /// stored property, and configs end up in log lines and crash reports.
  public var description: String {
    """
    PasspointConfig(apiKey: <redacted>, \
    environment: \(environment.baseURL.absoluteString), \
    eapType: \(eapType), \
    serverCACertificatePEM: \(serverCACertificatePEM == nil ? "nil" : "<set>"), \
    keychainAccessGroup: \(keychainAccessGroup ?? "nil"), \
    presetID: \(presetID ?? "nil"))
    """
  }

  public var debugDescription: String { description }
}
