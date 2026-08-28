import Foundation
import XCTest

@testable import HeliumPasspoint

/// The bundled CA is the one resource the SDK ships, and it is loaded from a
/// different place in each of the three integrations (SwiftPM, CocoaPods,
/// drag-and-drop). These tests cover the SwiftPM path; the CocoaPods path is
/// covered by the example app's build.
final class ServerCATests: XCTestCase {

  func testBundledCAIsPresent() throws {
    let pem = try ServerCA.bundledPEM()
    XCTAssertTrue(pem.contains("-----BEGIN CERTIFICATE-----"))
    XCTAssertTrue(pem.contains("-----END CERTIFICATE-----"))
  }

  func testBundledCAParsesAsAnX509Certificate() throws {
    let certificate = try XCTUnwrap(CertificateStore.parsePEM(ServerCA.bundledPEM()))
    XCTAssertNotNil(CertificateStore.subjectSummary(of: certificate))
  }

  /// A CA that has already expired would break every install, and the failure
  /// would surface as an opaque RADIUS error on device.
  func testBundledCAHasNotExpired() throws {
    let certificate = try XCTUnwrap(CertificateStore.parsePEM(ServerCA.bundledPEM()))
    let expiry = try XCTUnwrap(CertificateStore.expirationDate(of: certificate))
    XCTAssertGreaterThan(
      expiry, Date(),
      "the bundled server CA expired on \(ISO8601.string(from: expiry))")
  }

  func testResourceNameMatchesTheFileOnDisk() {
    XCTAssertEqual(ServerCA.resourceName, "serverCA")
    XCTAssertEqual(ServerCA.resourceExtension, "crt")
  }
}
