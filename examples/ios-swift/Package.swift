// swift-tools-version: 5.9
//
// A standalone package that consumes the SDK exactly as a partner app would.
// Because it depends on HeliumPasspoint as a separate module, it only compiles
// if the SDK's *public* surface is complete — which is why CI builds it:
//
//   cd examples/ios-swift
//   swift build --triple arm64-apple-ios15.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
//
// A real app would replace `path: "../.."` with:
//   .package(url: "https://github.com/helium/passpoint-sdk.git", from: "0.1.1")

import PackageDescription

let package = Package(
  name: "PasspointExample",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "PasspointExample", targets: ["PasspointExample"])
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .target(
      name: "PasspointExample",
      dependencies: [.product(name: "HeliumPasspoint", package: "passpoint-sdk")]
    )
  ]
)
