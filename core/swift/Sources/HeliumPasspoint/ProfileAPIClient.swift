import Foundation

/// Seam that lets the API client be tested without a network.
protocol HTTPTransport {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
  let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw PasspointError.apiError("Response was not HTTP")
    }
    return (data, http)
  }
}

/// Talks to the Helium inventory API. Contains no platform-specific code, so it
/// is exercised directly by the unit tests via a stub ``HTTPTransport``.
struct ProfileAPIClient {
  static let apiKeyHeader = "X-Helium-P-Api-Key"
  static let generateProfilePath = "preset/profile/generate"
  static let profileStatusPath = "preset/profile/status"
  static let statusSubscriberQueryParam = "subscriber_id"

  /// `application/x-www-form-urlencoded`-safe set: unreserved characters only,
  /// matching what Java's `URLEncoder` leaves alone (minus `*`, which it keeps
  /// but which is safe to escape).
  static let queryValueAllowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

  let baseURL: URL
  let apiKey: String
  let transport: HTTPTransport

  init(baseURL: URL, apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.transport = transport
  }

  /// Exchange a CSR for a signed Passpoint profile.
  func generateProfile(
    csr: String,
    subscriberID: String,
    eapType: EAPType,
    presetID: String?
  ) async throws -> IssuedProfile {
    var request = URLRequest(url: baseURL.appendingPathComponent(Self.generateProfilePath))
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: Self.apiKeyHeader)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    var body: [String: Any] = [
      "type": eapType.rawValue,
      "subscriber_id": subscriberID,
      "csr": csr,
    ]
    if let presetID, !presetID.isEmpty {
      body["preset_id"] = presetID
    }
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
      throw PasspointError.apiError("Failed to encode request body: \(error.localizedDescription)")
    }

    let (data, http) = try await perform(request)
    try Self.throwIfErrorStatus(http.statusCode, data: data)

    do {
      return try JSONDecoder().decode(ProfileResponse.self, from: data).issuedProfile
    } catch {
      throw PasspointError.apiError("Failed to decode profile: \(error.localizedDescription)")
    }
  }

  /// Server-side status for a subscriber, or `nil` when the server has no
  /// profile for them (HTTP 404).
  func profileStatus(subscriberID: String) async throws -> RemoteProfileStatus? {
    // URLQueryItem leaves "+" and "@" unescaped, and a server reading the query
    // string will decode "+" as a space. Percent-encode explicitly so a
    // subscriber ID survives the round trip and matches what the Android SDK
    // (URLEncoder) sends for the same input.
    guard
      let encoded = subscriberID.addingPercentEncoding(
        withAllowedCharacters: Self.queryValueAllowed),
      let url = URL(
        string: baseURL.appendingPathComponent(Self.profileStatusPath).absoluteString
          + "?\(Self.statusSubscriberQueryParam)=\(encoded)")
    else {
      throw PasspointError.apiError("Failed to construct status URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(apiKey, forHTTPHeaderField: Self.apiKeyHeader)
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, http) = try await perform(request)
    if http.statusCode == 404 { return nil }
    try Self.throwIfErrorStatus(http.statusCode, data: data)

    do {
      return try JSONDecoder().decode(StatusResponse.self, from: data).remoteStatus()
    } catch {
      throw PasspointError.apiError("Failed to decode status: \(error.localizedDescription)")
    }
  }

  // MARK: - Private

  private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      return try await transport.send(request)
    } catch let error as PasspointError {
      throw error
    } catch {
      throw PasspointError.networkError(error.localizedDescription)
    }
  }

  /// Maps HTTP status to error codes exactly as `contract.json` prescribes.
  static func throwIfErrorStatus(_ status: Int, data: Data) throws {
    guard !(200...299).contains(status) else { return }
    let body = String(data: data, encoding: .utf8) ?? ""
    switch status {
    case 401, 403:
      throw PasspointError.apiUnauthorized
    case 429:
      throw PasspointError.apiRateLimited("HTTP \(status)")
    default:
      throw PasspointError.apiError("HTTP \(status): \(body)")
    }
  }
}
