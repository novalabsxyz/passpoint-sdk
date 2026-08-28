import Foundation

/// Locates the CA certificate bundled with the SDK.
///
/// The same source tree ships three ways, and each puts resources somewhere
/// different: SwiftPM generates `Bundle.module`, CocoaPods generates a nested
/// `HeliumPasspoint.bundle`, and a plain drag-and-drop integration leaves the
/// file in the main bundle.
enum ServerCA {
  static let resourceName = "serverCA"
  static let resourceExtension = "crt"

  static func bundledPEM() throws -> String {
    for bundle in candidateBundles() {
      if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
        let contents = try? String(contentsOf: url, encoding: .utf8)
      {
        return contents
      }
    }
    throw PasspointError.certificateParseFailed(
      "\(resourceName).\(resourceExtension) not found in any bundle")
  }

  private static func candidateBundles() -> [Bundle] {
    #if SWIFT_PACKAGE
      return [Bundle.module]
    #else
      let sdkBundle = Bundle(for: BundleToken.self)
      var bundles: [Bundle] = []
      // CocoaPods `resource_bundles` nests a bundle inside the pod's bundle.
      // The native pod names it "HeliumPasspoint"; the React Native pod uses
      // "HeliumPasspointRN" so the two can coexist in one app.
      for name in ["HeliumPasspoint", "HeliumPasspointRN"] {
        if let url = sdkBundle.url(forResource: name, withExtension: "bundle"),
          let nested = Bundle(url: url)
        {
          bundles.append(nested)
        }
      }
      bundles.append(sdkBundle)
      bundles.append(.main)
      return bundles
    #endif
  }
}

/// Anchor class for `Bundle(for:)`. Unused under SwiftPM.
private final class BundleToken {}
