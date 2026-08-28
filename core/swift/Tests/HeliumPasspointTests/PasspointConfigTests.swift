import Foundation
import XCTest

@testable import HeliumPasspoint

final class PasspointConfigTests: XCTestCase {

  // MARK: - Environment

  func testNamedEnvironmentsResolve() {
    XCTAssertEqual(PasspointEnvironment.named("production"), .production)
    XCTAssertEqual(PasspointEnvironment.named("development"), .development)
    XCTAssertEqual(PasspointEnvironment.named("poc"), .poc)
  }

  /// Matches the TypeScript SDK, which also falls back rather than throwing.
  func testUnknownNameFallsBackToProduction() {
    XCTAssertEqual(PasspointEnvironment.named("staging"), .production)
    XCTAssertEqual(PasspointEnvironment.named(""), .production)
  }

  func testHTTPPrefixIsTreatedAsACustomBaseURL() {
    let environment = PasspointEnvironment.named("https://api.internal.test/api/inventory/v1")
    XCTAssertEqual(
      environment.baseURL.absoluteString, "https://api.internal.test/api/inventory/v1")
  }

  func testCustomBaseURLLosesTrailingSlashes() {
    XCTAssertEqual(
      PasspointEnvironment.named("https://api.internal.test/v1///").baseURL.absoluteString,
      "https://api.internal.test/v1")
    XCTAssertEqual(
      PasspointEnvironment.custom(URL(string: "https://api.internal.test/v1/")!)
        .baseURL.absoluteString,
      "https://api.internal.test/v1")
  }

  /// A base URL with a trailing slash must not produce a double slash once the
  /// API client appends its path.
  func testTrimmedCustomURLAppendsCleanly() {
    let base = PasspointEnvironment.named("https://api.internal.test/v1/").baseURL
    XCTAssertEqual(
      base.appendingPathComponent("preset/profile/generate").absoluteString,
      "https://api.internal.test/v1/preset/profile/generate")
  }

  // MARK: - Defaults

  func testDefaults() {
    let config = PasspointConfig(apiKey: "key")
    XCTAssertEqual(config.environment, .production)
    XCTAssertEqual(config.eapType, .tls)
    XCTAssertNil(config.serverCACertificatePEM)
    XCTAssertNil(config.keychainAccessGroup)
    XCTAssertNil(config.presetID)
  }

  // MARK: - Validation

  func testValidationAcceptsANonEmptyKey() throws {
    XCTAssertNoThrow(try PasspointConfig(apiKey: "key").validated())
  }

  func testValidationRejectsABlankKey() {
    for key in ["", "   ", "\n\t"] {
      XCTAssertThrowsError(try PasspointConfig(apiKey: key).validated()) { error in
        XCTAssertEqual((error as? PasspointError)?.code, .invalidConfig)
      }
    }
  }

  // MARK: - ISO 8601

  func testParsesTimestampsWithoutFractionalSeconds() {
    let date = ISO8601.date(from: "2035-01-01T00:00:00Z")
    XCTAssertEqual(date.map(ISO8601.string(from:)), "2035-01-01T00:00:00Z")
  }

  func testParsesTimestampsWithFractionalSeconds() {
    let date = ISO8601.date(from: "2035-01-01T00:00:00.500Z")
    XCTAssertEqual(date.map(ISO8601.string(from:)), "2035-01-01T00:00:00Z")
  }

  func testParsesTimestampsWithANumericOffset() {
    let date = ISO8601.date(from: "2035-01-01T01:00:00+01:00")
    XCTAssertEqual(date.map(ISO8601.string(from:)), "2035-01-01T00:00:00Z")
  }

  func testRejectsNonsense() {
    XCTAssertNil(ISO8601.date(from: "whenever"))
    XCTAssertNil(ISO8601.date(from: ""))
  }

  func testFormatIsStableAcrossARoundTrip() throws {
    let original = "2035-01-01T00:00:00Z"
    let date = try XCTUnwrap(ISO8601.date(from: original))
    XCTAssertEqual(ISO8601.string(from: date), original)
  }

  // MARK: - ISO 8601 acceptance parity

  /// The same table is asserted in the Kotlin suite
  /// (`accepts the same timestamps as the iOS SDK`). Both SDKs must agree on
  /// which server timestamps parse and what they parse to, or `expiresAt`
  /// silently differs by platform.
  func testAcceptsTheSameTimestampsAsTheAndroidSDK() {
    let accepted: [(String, String)] = [
      ("2035-01-01T00:00:00Z", "2035-01-01T00:00:00Z"),
      ("2035-01-01T00:00:00.500Z", "2035-01-01T00:00:00Z"),
      ("2035-01-01T00:00:00.123456Z", "2035-01-01T00:00:00Z"),
      ("2035-01-01T01:00:00+01:00", "2035-01-01T00:00:00Z"),
      ("2035-01-01T01:00:00+0100", "2035-01-01T00:00:00Z"),
      ("2035-01-01T00:00Z", "2035-01-01T00:00:00Z"),
      ("2035-01-01t00:00:00z", "2035-01-01T00:00:00Z"),
      ("  2035-01-01T00:00:00Z  ", "2035-01-01T00:00:00Z"),
      ("1969-07-20T20:17:00Z", "1969-07-20T20:17:00Z"),
    ]
    for (input, expected) in accepted {
      XCTAssertEqual(
        ISO8601.date(from: input).map(ISO8601.string(from:)), expected,
        "parsing \(input)")
    }

    for input in ["whenever", "", "2035-13-01T00:00:00Z", "2035-01-01"] {
      XCTAssertNil(ISO8601.date(from: input), "should not parse \(input)")
    }
  }

  func testNormalizeIsIdempotent() {
    for input in ["2035-01-01T00:00:00Z", "2035-01-01t00:00z", "2035-01-01T01:00:00+0100"] {
      let once = ISO8601.normalize(input)
      XCTAssertEqual(ISO8601.normalize(once), once, "normalizing \(input) twice")
    }
  }

  // MARK: - TLS version

  /// An unrecognised `tls_version` must not fail the install — the field is a
  /// preference and the OS negotiates upward anyway.
  func testUnknownTLSVersionFallsBackTo1_2() {
    XCTAssertEqual(TLSVersionPreference.from("1.0"), .v1_0)
    XCTAssertEqual(TLSVersionPreference.from("1.1"), .v1_1)
    XCTAssertEqual(TLSVersionPreference.from("1.2"), .v1_2)
    for unknown in ["1.3", "", "TLSv1.2", "garbage"] {
      XCTAssertEqual(TLSVersionPreference.from(unknown), .v1_2, "for \(unknown)")
    }
  }
}
