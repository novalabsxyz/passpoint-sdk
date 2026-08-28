require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
repo_url = package["repository"]["url"].sub(/\Agit\+/, "").sub(/\.git\z/, "")

# CocoaPods distribution of the native Swift SDK, for iOS apps that are not
# React Native and prefer CocoaPods to SwiftPM. Builds core/swift/ only — the
# React Native bridge in ios/ is deliberately excluded.
#
#   pod 'HeliumPasspoint', :git => 'https://github.com/novalabsxyz/passpoint-sdk.git', :tag => 'v1.0.0'
#
# SwiftPM users get the same sources through the root Package.swift.
Pod::Spec.new do |s|
  s.name         = "HeliumPasspoint"
  s.version      = package["version"]
  s.summary      = "Helium Passpoint (Hotspot 2.0) WiFi offload SDK for iOS"
  s.homepage     = repo_url
  s.license      = package["license"]
  s.author       = package["author"]
  # Tags are vX.Y.Z — CocoaPods needs the literal tag name, unlike SwiftPM.
  s.source       = { :git => "#{repo_url}.git", :tag => "v#{s.version}" }

  s.platform     = :ios, "15.0"
  s.swift_version = "5.9"

  s.source_files = "core/swift/Sources/HeliumPasspoint/**/*.swift"
  s.resource_bundles = {
    "HeliumPasspoint" => ["core/swift/Sources/HeliumPasspoint/Resources/**/*"]
  }

  s.frameworks = "Foundation", "Security", "NetworkExtension"
end
