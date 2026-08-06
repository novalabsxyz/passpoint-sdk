import Foundation
import XCTest

@testable import HeliumPasspoint

/// The keychain itself is not exercised — these tests must never write to the
/// developer's login keychain. What is asserted is the labelling invariant that
/// makes scoped deletion possible.
///
/// `deleteSDKCertificates()` deletes by label rather than by class, because the
/// access group the SDK must use is shared with the app's other
/// NetworkExtension components. That is only safe if every label the SDK writes
/// starts with `labelPrefix`.
final class KeychainManagerTests: XCTestCase {

  func testEveryLabelTheSDKWritesCarriesThePrefix() {
    let labels = [
      KeychainManager.defaultCertificateLabel,
      KeychainManager.rootCALabel,
      KeychainManager.caChainLabel(index: 0),
      KeychainManager.caChainLabel(index: 7),
    ]
    for label in labels {
      XCTAssertTrue(
        label.hasPrefix(KeychainManager.labelPrefix),
        "\(label) would survive a scoped delete")
    }
  }

  func testCAChainLabelsAreDistinctPerIndex() {
    let labels = (0..<5).map { KeychainManager.caChainLabel(index: $0) }
    XCTAssertEqual(Set(labels).count, labels.count)
  }

  func testCAChainLabelMatchesTheHistoricalFormat() {
    // Certificates written by earlier SDK versions must still be found and
    // removed on upgrade.
    XCTAssertEqual(KeychainManager.caChainLabel(index: 2), "HeliumPasspoint CA Chain 2")
    XCTAssertEqual(KeychainManager.defaultCertificateLabel, "HeliumPasspoint Cert")
    XCTAssertEqual(KeychainManager.rootCALabel, "HeliumPasspoint Root CA")
  }

  func testKeySizeIsRSA2048() {
    XCTAssertEqual(KeychainManager.keySizeBits, 2048)
  }
}
