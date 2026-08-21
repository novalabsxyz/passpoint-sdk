require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
repo_url = package["repository"]["url"].sub(/\Agit\+/, "").sub(/\.git\z/, "")

Pod::Spec.new do |s|
  s.name         = "helium-passpoint-sdk"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = repo_url
  s.license      = package["license"]
  s.author       = package["author"]
  s.source       = { :git => "#{repo_url}.git", :tag => s.version }

  s.platform     = :ios, "15.0"
  s.swift_version = "5.9"

  s.source_files = "ios/**/*.{swift,h,m,mm}"
  s.resource_bundles = {
    "HeliumPasspointSDK" => ["ios/Resources/**/*"]
  }

  # No external iOS dependencies — CSR generation uses the built-in Security framework.

  install_modules_dependencies(s)
end
