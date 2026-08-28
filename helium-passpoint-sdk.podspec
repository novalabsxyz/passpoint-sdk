require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
repo_url = package["repository"]["url"].sub(/\Agit\+/, "").sub(/\.git\z/, "")

# React Native pod. Compiles the shared Swift core (core/swift/) together with
# the thin bridge in ios/ into one module, which is why the bridge needs no
# `import HeliumPasspoint`.
#
# Native Swift apps do not use this podspec — they use Package.swift (SwiftPM)
# or HeliumPasspoint.podspec (CocoaPods), both of which build core/swift/ alone.
Pod::Spec.new do |s|
  s.name         = "helium-passpoint-sdk"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = repo_url
  s.license      = package["license"]
  s.author       = package["author"]
  # Tags are vX.Y.Z — CocoaPods needs the literal tag name, unlike SwiftPM.
  s.source       = { :git => "#{repo_url}.git", :tag => "v#{s.version}" }

  s.platform     = :ios, "15.0"
  s.swift_version = "5.9"

  s.source_files = [
    "core/swift/Sources/HeliumPasspoint/**/*.swift",
    "ios/**/*.{swift,h,m,mm}",
  ]
  # Deliberately not "HeliumPasspoint": a brownfield app could install this pod
  # and the native HeliumPasspoint pod, and two bundles with the same name
  # produce the same output path. ServerCA.swift looks for both names.
  s.resource_bundles = {
    "HeliumPasspointRN" => ["core/swift/Sources/HeliumPasspoint/Resources/**/*"]
  }

  # No external iOS dependencies — CSR generation uses the built-in Security framework.

  install_modules_dependencies(s)
end
