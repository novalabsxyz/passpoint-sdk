import Foundation
import XCTest

@testable import HeliumPasspoint

final class ProfileAPIClientTests: XCTestCase {
  private let baseURL = URL(string: "https://api.example.test/api/inventory/v1")!
  private let apiKey = "test-api-key"

  private func client(_ transport: HTTPTransport) -> ProfileAPIClient {
    ProfileAPIClient(baseURL: baseURL, apiKey: apiKey, transport: transport)
  }

  // MARK: - generateProfile

  func testGenerateProfileDecodesTheResponse() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("profile-response.json"))
    let profile = try await client(transport).generateProfile(
      csr: "csr", subscriberID: "subscriber-42", eapType: .tls, presetID: nil)

    XCTAssertEqual(profile.friendlyName, "Helium WiFi")
    XCTAssertEqual(profile.domainName, "helium.example")
    XCTAssertEqual(profile.naiRealmNames, ["helium.example", "roaming.helium.example"])
    XCTAssertEqual(profile.trustedServerNames, ["radius.helium.example"])
    XCTAssertEqual(profile.tlsVersion, "1.2")
    XCTAssertTrue(profile.certificate.contains("BEGIN CERTIFICATE"))
    XCTAssertEqual(profile.caChain.count, 1)
  }

  func testGenerateProfileSendsTheExpectedRequest() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("profile-response.json"))
    _ = try await client(transport).generateProfile(
      csr: "the-csr", subscriberID: "subscriber-42", eapType: .tls, presetID: nil)

    let request = try XCTUnwrap(transport.lastRequest)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://api.example.test/api/inventory/v1/preset/profile/generate")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Helium-P-Api-Key"), apiKey)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(body["type"] as? Int, 13)
    XCTAssertEqual(body["subscriber_id"] as? String, "subscriber-42")
    XCTAssertEqual(body["csr"] as? String, "the-csr")
    XCTAssertNil(body["preset_id"], "preset_id must be omitted when unset")
  }

  func testGenerateProfileIncludesPresetIDWhenSet() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("profile-response.json"))
    _ = try await client(transport).generateProfile(
      csr: "csr", subscriberID: "s", eapType: .tls, presetID: "preset-uuid")

    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(transport.lastRequest?.httpBody))
        as? [String: Any])
    XCTAssertEqual(body["preset_id"] as? String, "preset-uuid")
  }

  func testGenerateProfileOmitsBlankPresetID() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("profile-response.json"))
    _ = try await client(transport).generateProfile(
      csr: "csr", subscriberID: "s", eapType: .tls, presetID: "")

    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(transport.lastRequest?.httpBody))
        as? [String: Any])
    XCTAssertNil(body["preset_id"])
  }

  func testGenerateProfileSendsTheConfiguredEAPType() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("profile-response.json"))
    _ = try await client(transport).generateProfile(
      csr: "csr", subscriberID: "s", eapType: .ttls, presetID: nil)

    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(transport.lastRequest?.httpBody))
        as? [String: Any])
    XCTAssertEqual(body["type"] as? Int, 21)
  }

  func testGenerateProfileDefaultsMissingTLSVersion() async throws {
    let body = """
      {"friendly_name":"n","domain_name":"d","nai_realm_names":[],
       "trusted_server_names":[],"certificate":"c","ca_chain":[]}
      """
    let transport = StubTransport(status: 200, body: body)
    let profile = try await client(transport).generateProfile(
      csr: "csr", subscriberID: "s", eapType: .tls, presetID: nil)
    XCTAssertEqual(profile.tlsVersion, "1.2")
  }

  func testGenerateProfileRejectsMalformedJSON() async {
    let transport = StubTransport(status: 200, body: "{not json")
    await assertThrowsPasspointError(.apiError) {
      try await self.client(transport).generateProfile(
        csr: "csr", subscriberID: "s", eapType: .tls, presetID: nil)
    }
  }

  func testGenerateProfileRejectsAMissingField() async {
    let transport = StubTransport(status: 200, body: #"{"friendly_name":"n"}"#)
    await assertThrowsPasspointError(.apiError) {
      try await self.client(transport).generateProfile(
        csr: "csr", subscriberID: "s", eapType: .tls, presetID: nil)
    }
  }

  /// 404 is only meaningful on the status endpoint; here it is a plain error.
  func testGenerateProfileTreats404AsAnError() async {
    let transport = StubTransport(status: 404, body: "")
    await assertThrowsPasspointError(.apiError) {
      try await self.client(transport).generateProfile(
        csr: "csr", subscriberID: "s", eapType: .tls, presetID: nil)
    }
  }

  // MARK: - Status mapping (contract.json httpStatusMapping)

  func testStatusCodesMapToContractErrorCodes() async throws {
    let cases: [(Int, PasspointErrorCode)] = [
      (400, .apiError),
      (401, .apiUnauthorized),
      (403, .apiUnauthorized),
      (429, .apiRateLimited),
      (500, .apiError),
      (503, .apiError),
    ]
    for (status, expected) in cases {
      let transport = StubTransport(status: status, body: "boom")
      await assertThrowsPasspointError(expected) {
        try await self.client(transport).generateProfile(
          csr: "csr", subscriberID: "s", eapType: .tls, presetID: nil)
      }
    }
  }

  func testTransportFailureBecomesNetworkError() async {
    struct Offline: Error {}
    let transport = StubTransport(failure: Offline())
    await assertThrowsPasspointError(.networkError) {
      try await self.client(transport).generateProfile(
        csr: "csr", subscriberID: "s", eapType: .tls, presetID: nil)
    }
  }

  // MARK: - profileStatus

  func testProfileStatusDecodesTheResponse() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("status-response.json"))
    let result = try await client(transport).profileStatus(subscriberID: "subscriber-42")
    let status = try XCTUnwrap(result)

    XCTAssertEqual(status.subscriberID, "subscriber-42")
    XCTAssertEqual(status.presetID, "0f9d2b1e-4c3a-4f7b-9d21-6a8c5e0b1234")
    XCTAssertEqual(status.eapType, 13)
    XCTAssertEqual(status.expiresAt.map(ISO8601.string(from:)), "2035-01-01T00:00:00Z")
    XCTAssertEqual(status.expiresAtRaw, "2035-01-01T00:00:00Z")
    XCTAssertTrue(status.active)
  }

  func testProfileStatusSendsTheExpectedRequest() async throws {
    let transport = StubTransport(status: 200, body: try Fixtures.string("status-response.json"))
    _ = try await client(transport).profileStatus(subscriberID: "subscriber-42")

    let request = try XCTUnwrap(transport.lastRequest)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://api.example.test/api/inventory/v1/preset/profile/status?subscriber_id=subscriber-42")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Helium-P-Api-Key"), apiKey)
    XCTAssertNil(request.httpBody)
  }

  /// URLQueryItem leaves "+" alone and a server decodes it as a space, so a
  /// subscriber ID containing "+" would silently query for a different one.
  /// These expectations are duplicated verbatim in the Kotlin suite
  /// (`builds the same status url as the iOS SDK`) so the two agree.
  func testProfileStatusPercentEncodesTheSubscriberID() async throws {
    let cases = [
      ("user+1@example.com", "user%2B1%40example.com"),
      ("has space", "has%20space"),
      ("plain-123", "plain-123"),
      ("sl/ash&amp", "sl%2Fash%26amp"),
      ("unicode-Ä", "unicode-%C3%84"),
      ("tilde~dot.", "tilde~dot."),
    ]
    for (subscriberID, expected) in cases {
      let transport = StubTransport(
        status: 200, body: try Fixtures.string("status-response.json"))
      _ = try await client(transport).profileStatus(subscriberID: subscriberID)
      XCTAssertEqual(
        transport.lastRequest?.url?.absoluteString,
        "\(baseURL.absoluteString)/preset/profile/status?subscriber_id=\(expected)",
        "encoding of \(subscriberID)")
    }
  }

  /// 404 means "the server has no profile for this subscriber", not a failure.
  func testProfileStatusReturnsNilOn404() async throws {
    let transport = StubTransport(status: 404, body: #"{"detail":"not found"}"#)
    let status = try await client(transport).profileStatus(subscriberID: "nobody")
    XCTAssertNil(status)
  }

  func testProfileStatusUnauthorized() async {
    let transport = StubTransport(status: 401, body: "")
    await assertThrowsPasspointError(.apiUnauthorized) {
      try await self.client(transport).profileStatus(subscriberID: "s")
    }
  }

  func testProfileStatusRateLimited() async {
    let transport = StubTransport(status: 429, body: "")
    await assertThrowsPasspointError(.apiRateLimited) {
      try await self.client(transport).profileStatus(subscriberID: "s")
    }
  }

  /// An unrecognised timestamp must not fail the call: the raw string still
  /// reaches the caller, and `active` is what callers branch on. The React
  /// Native bridge forwards `expiresAtRaw` verbatim, so a server format this
  /// SDK cannot parse behaves exactly as it did before the native split.
  func testProfileStatusKeepsAnUnparseableExpiryAsRaw() async throws {
    let body = """
      {"subscriber_id":"s","preset_id":"p","eap_type":13,
       "expires_at":"2027-08-06 12:34:56+00","active":true}
      """
    let transport = StubTransport(status: 200, body: body)
    let result = try await client(transport).profileStatus(subscriberID: "s")
    let status = try XCTUnwrap(result)

    XCTAssertNil(status.expiresAt)
    XCTAssertEqual(status.expiresAtRaw, "2027-08-06 12:34:56+00")
    XCTAssertTrue(status.active)
  }

  func testProfileStatusPreservesTheServersExactTimestamp() async throws {
    for raw in [
      "2035-01-01T00:00:00Z",
      "2035-01-01T00:00:00.123456Z",
      "2035-01-01T01:00:00+01:00",
      "not a date at all",
    ] {
      let body = """
        {"subscriber_id":"s","preset_id":"p","eap_type":13,
         "expires_at":"\(raw)","active":true}
        """
      let transport = StubTransport(status: 200, body: body)
      let result = try await client(transport).profileStatus(subscriberID: "s")
      XCTAssertEqual(try XCTUnwrap(result).expiresAtRaw, raw)
    }
  }

  func testProfileStatusRejectsAMissingExpiry() async {
    let body = #"{"subscriber_id":"s","preset_id":"p","eap_type":13,"active":true}"#
    let transport = StubTransport(status: 200, body: body)
    await assertThrowsPasspointError(.apiError) {
      try await self.client(transport).profileStatus(subscriberID: "s")
    }
  }

  func testProfileStatusAcceptsFractionalSeconds() async throws {
    let body = """
      {"subscriber_id":"s","preset_id":"p","eap_type":13,
       "expires_at":"2035-01-01T00:00:00.123Z","active":false}
      """
    let transport = StubTransport(status: 200, body: body)
    let result = try await client(transport).profileStatus(subscriberID: "s")
    let status = try XCTUnwrap(result)
    XCTAssertEqual(status.expiresAt.map(ISO8601.string(from:)), "2035-01-01T00:00:00Z")
    XCTAssertEqual(status.expiresAtRaw, "2035-01-01T00:00:00.123Z", "raw is passed through unchanged")
    XCTAssertFalse(status.active)
  }
}
