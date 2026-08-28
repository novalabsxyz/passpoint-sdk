// swift-tools-version: 5.9
//
// SwiftPM resolves a package from the repository root only — there is no
// subdirectory support — so this manifest lives here while the sources sit
// under core/swift/. React Native consumers never see this file; they get the
// same sources through helium-passpoint-sdk.podspec.

import PackageDescription

let package = Package(
  name: "HeliumPasspoint",
  platforms: [
    .iOS(.v15),
    // macOS is supported so the platform-independent half of the SDK (CSR
    // building, DER parsing, the API client) can be unit-tested with
    // `swift test`. PasspointClient itself is iOS-only.
    .macOS(.v12),
  ],
  products: [
    .library(name: "HeliumPasspoint", targets: ["HeliumPasspoint"])
  ],
  targets: [
    .target(
      name: "HeliumPasspoint",
      path: "core/swift/Sources/HeliumPasspoint",
      resources: [.process("Resources")]
    ),
    // Fixtures deliberately live in core/testdata/ rather than in this target:
    // the Kotlin and TypeScript suites read the same files, so all three SDKs
    // are tested against identical inputs. Tests locate them from #filePath.
    .testTarget(
      name: "HeliumPasspointTests",
      dependencies: ["HeliumPasspoint"],
      path: "core/swift/Tests/HeliumPasspointTests"
    ),
  ]
)
