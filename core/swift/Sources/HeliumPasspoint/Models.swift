import Foundation

/// Details of the Passpoint credential currently installed on this device.
public struct CertificateInfo: Equatable, Sendable {
  /// Whether a Helium Passpoint credential is installed.
  public let isInstalled: Bool
  /// Client certificate expiry, or `nil` when nothing is installed.
  public let expiresAt: Date?
  /// Client certificate subject summary, or `nil` when nothing is installed.
  public let subject: String?
  /// Passpoint domain (HomeSP FQDN) of the installed profile.
  public let domain: String?
  /// Human-readable profile name shown in iOS Settings.
  public let friendlyName: String?

  public init(
    isInstalled: Bool,
    expiresAt: Date? = nil,
    subject: String? = nil,
    domain: String? = nil,
    friendlyName: String? = nil
  ) {
    self.isInstalled = isInstalled
    self.expiresAt = expiresAt
    self.subject = subject
    self.domain = domain
    self.friendlyName = friendlyName
  }

  /// The "nothing installed" value.
  public static let notInstalled = CertificateInfo(isInstalled: false)
}

/// The server's view of a subscriber's profile, from `GET /preset/profile/status`.
public struct RemoteProfileStatus: Equatable, Sendable {
  /// Subscriber identifier the certificate was issued to.
  public let subscriberID: String
  /// UUID of the preset used to issue the certificate.
  public let presetID: String
  /// IANA EAP method number (13 = EAP-TLS).
  public let eapType: Int
  /// Certificate expiry, or `nil` when the server sent a timestamp this SDK
  /// cannot parse. ``expiresAtRaw`` always carries the server's exact string,
  /// so an unrecognised format degrades rather than failing the call.
  public let expiresAt: Date?
  /// The `expires_at` string exactly as the server sent it.
  public let expiresAtRaw: String
  /// Whether the certificate has not yet expired.
  public let active: Bool

  public init(
    subscriberID: String,
    presetID: String,
    eapType: Int,
    expiresAt: Date?,
    expiresAtRaw: String,
    active: Bool
  ) {
    self.subscriberID = subscriberID
    self.presetID = presetID
    self.eapType = eapType
    self.expiresAt = expiresAt
    self.expiresAtRaw = expiresAtRaw
    self.active = active
  }
}

/// A profile issued by the inventory API in response to a CSR.
struct IssuedProfile: Equatable {
  let friendlyName: String
  let domainName: String
  let naiRealmNames: [String]
  let trustedServerNames: [String]
  let tlsVersion: String
  let certificate: String
  let caChain: [String]
}

// MARK: - Wire types

/// `POST /preset/profile/generate` response body.
struct ProfileResponse: Decodable {
  let friendlyName: String
  let domainName: String
  let naiRealmNames: [String]
  let trustedServerNames: [String]
  let tlsVersion: String?
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

  var issuedProfile: IssuedProfile {
    IssuedProfile(
      friendlyName: friendlyName,
      domainName: domainName,
      naiRealmNames: naiRealmNames,
      trustedServerNames: trustedServerNames,
      tlsVersion: tlsVersion ?? "1.2",
      certificate: certificate,
      caChain: caChain
    )
  }
}

/// `GET /preset/profile/status` response body.
struct StatusResponse: Decodable {
  let subscriberID: String
  let presetID: String
  let eapType: Int
  let expiresAt: String
  let active: Bool

  enum CodingKeys: String, CodingKey {
    case subscriberID = "subscriber_id"
    case presetID = "preset_id"
    case eapType = "eap_type"
    case expiresAt = "expires_at"
    case active
  }

  /// An `expires_at` the SDK cannot parse is surfaced as `nil` rather than
  /// throwing: the server's string still reaches the caller through
  /// ``RemoteProfileStatus/expiresAtRaw``, and `active` is the field callers
  /// actually branch on.
  func remoteStatus() -> RemoteProfileStatus {
    RemoteProfileStatus(
      subscriberID: subscriberID,
      presetID: presetID,
      eapType: eapType,
      expiresAt: ISO8601.date(from: expiresAt),
      expiresAtRaw: expiresAt,
      active: active
    )
  }
}

// MARK: - ISO 8601

/// Date handling shared by the API client and the React Native bridge.
///
/// The inventory API emits RFC 3339 timestamps, sometimes with fractional
/// seconds. Parsing accepts both; formatting always produces the canonical
/// no-fraction form so the JSON the bridge hands to TypeScript is stable.
enum ISO8601 {
  static func date(from string: String) -> Date? {
    let normalized = normalize(string)

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: normalized) { return date }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: normalized)
  }

  /// Widen what the strict RFC 3339 parsers accept, so the Swift and Kotlin
  /// SDKs agree on which server timestamps are parseable. The rules are
  /// mirrored exactly in `Iso8601.normalize` on the Kotlin side, and the same
  /// table of inputs is asserted in both suites.
  ///
  /// 1. surrounding whitespace is ignored
  /// 2. the `t` separator and `z` designator may be lower case
  /// 3. a numeric offset may omit the colon (`+0100`)
  /// 4. seconds may be omitted (`2035-01-01T00:00Z`)
  static func normalize(_ string: String) -> String {
    var value = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    // "+0100" / "-0530" -> "+01:00" / "-05:30"
    if value.count >= 5 {
      let offsetStart = value.index(value.endIndex, offsetBy: -5)
      let tail = value[offsetStart...]
      if let sign = tail.first, sign == "+" || sign == "-",
        tail.dropFirst().allSatisfy(\.isNumber)
      {
        let digits = tail.dropFirst()
        let hours = digits.prefix(2)
        let minutes = digits.suffix(2)
        value.replaceSubrange(offsetStart..., with: "\(sign)\(hours):\(minutes)")
      }
    }

    // "2035-01-01T00:00Z" -> "2035-01-01T00:00:00Z"
    if let tIndex = value.firstIndex(of: "T") {
      let time = value[value.index(after: tIndex)...]
      let clock = time.prefix { $0.isNumber || $0 == ":" }
      if clock.filter({ $0 == ":" }).count == 1 {
        let insertAt = value.index(value.index(after: tIndex), offsetBy: clock.count)
        value.insert(contentsOf: ":00", at: insertAt)
      }
    }

    return value
  }

  static func string(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
