import Foundation
import XCTest

@testable import HeliumPasspoint

/// Asserts the Swift SDK agrees with `core/contract/contract.json`. The Kotlin
/// and TypeScript suites assert the same file, so a drift in any one SDK fails
/// that SDK's build with the exact missing symbol.
final class ContractConformanceTests: XCTestCase {
  private var contract: [String: Any]!

  override func setUpWithError() throws {
    try super.setUpWithError()
    contract = try Fixtures.contract()
  }

  func testErrorCodesMatchExactly() throws {
    let expected = Set(try XCTUnwrap(contract["errorCodes"] as? [String]))
    let actual = Set(PasspointErrorCode.allCases.map(\.rawValue))

    XCTAssertEqual(
      actual.subtracting(expected), [], "codes in Swift that are missing from contract.json")
    XCTAssertEqual(
      expected.subtracting(actual), [], "codes in contract.json that are missing from Swift")
  }

  func testEnvironmentBaseURLsMatch() throws {
    let expected = try XCTUnwrap(contract["environments"] as? [String: String])
    for (name, url) in expected {
      XCTAssertEqual(
        PasspointEnvironment.named(name).baseURL.absoluteString, url,
        "base URL for \(name)")
    }
    XCTAssertEqual(expected.count, 3, "a new environment needs a case in PasspointEnvironment")
  }

  func testDefaultEnvironmentMatches() throws {
    let name = try XCTUnwrap(contract["defaultEnvironment"] as? String)
    XCTAssertEqual(PasspointConfig(apiKey: "k").environment, PasspointEnvironment.named(name))
  }

  func testEAPTypesMatch() throws {
    let expected = try XCTUnwrap(contract["eapTypes"] as? [String: Int])
    XCTAssertEqual(expected["TLS"], EAPType.tls.rawValue)
    XCTAssertEqual(expected["TTLS"], EAPType.ttls.rawValue)
    XCTAssertEqual(expected["PEAP"], EAPType.peap.rawValue)
    XCTAssertEqual(expected.count, EAPType.allCases.count)
  }

  func testDefaultEAPTypeMatches() throws {
    let expected = try XCTUnwrap(contract["defaultEapType"] as? Int)
    XCTAssertEqual(PasspointConfig(apiKey: "k").eapType.rawValue, expected)
  }

  func testAPIPathsAndHeaderMatch() throws {
    let api = try XCTUnwrap(contract["api"] as? [String: String])
    XCTAssertEqual(api["apiKeyHeader"], ProfileAPIClient.apiKeyHeader)
    XCTAssertEqual(api["generateProfilePath"], ProfileAPIClient.generateProfilePath)
    XCTAssertEqual(api["profileStatusPath"], ProfileAPIClient.profileStatusPath)
    XCTAssertEqual(
      api["statusSubscriberQueryParam"], ProfileAPIClient.statusSubscriberQueryParam)
  }

  func testCSRCommonNameTemplateMatches() throws {
    let csr = try XCTUnwrap(contract["csr"] as? [String: Any])
    let template = try XCTUnwrap(csr["commonNameTemplate"] as? String)
    let expected = template.replacingOccurrences(of: "{subscriberId}", with: "abc-123")
    XCTAssertEqual(CSRGenerator.commonName(subscriberID: "abc-123"), expected)
  }

  /// The key size the SDK actually generates, not the one the tests happen to
  /// hand it — dropping to RSA-1024 must fail here.
  func testCSRKeySizeMatches() throws {
    let csr = try XCTUnwrap(contract["csr"] as? [String: Any])
    XCTAssertEqual(csr["keySizeBits"] as? Int, KeychainManager.keySizeBits)
  }

  /// `.rsaSignatureMessagePKCS1v15SHA256` is what CSRGenerator signs with, and
  /// the sha256WithRSA OID is what it writes into the signatureAlgorithm field.
  func testCSRSignatureAlgorithmMatches() throws {
    let csr = try XCTUnwrap(contract["csr"] as? [String: Any])
    XCTAssertEqual(csr["signatureAlgorithm"] as? String, "SHA256withRSA")
    XCTAssertEqual(
      DER.OID.sha256WithRSA,
      Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]))
  }

  /// Without this the mapping loop below iterates whatever happens to be in the
  /// file — deleting every status key would leave all three suites green.
  func testHTTPStatusMappingCoversTheExpectedStatuses() throws {
    let mapping = try XCTUnwrap(contract["httpStatusMapping"] as? [String: String])
    let keys = Set(mapping.keys).subtracting(["$comment"])
    XCTAssertEqual(keys, ["401", "403", "429", "default"])
  }

  func testHTTPStatusMappingMatches() throws {
    let mapping = try XCTUnwrap(contract["httpStatusMapping"] as? [String: String])
    for (key, expectedCode) in mapping where key != "default" && key != "$comment" {
      let status = try XCTUnwrap(Int(key))
      do {
        try ProfileAPIClient.throwIfErrorStatus(status, data: Data())
        XCTFail("HTTP \(status) should have thrown")
      } catch let error as PasspointError {
        XCTAssertEqual(error.code.rawValue, expectedCode, "mapping for HTTP \(status)")
      }
    }

    let fallback = try XCTUnwrap(mapping["default"])
    for status in [400, 418, 500, 502] {
      do {
        try ProfileAPIClient.throwIfErrorStatus(status, data: Data())
        XCTFail("HTTP \(status) should have thrown")
      } catch let error as PasspointError {
        XCTAssertEqual(error.code.rawValue, fallback, "default mapping for HTTP \(status)")
      }
    }
  }

  func testSuccessStatusesDoNotThrow() throws {
    for status in [200, 201, 204, 299] {
      XCTAssertNoThrow(try ProfileAPIClient.throwIfErrorStatus(status, data: Data()))
    }
  }
}
