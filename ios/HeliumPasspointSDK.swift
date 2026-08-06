import Foundation
import React

/// React Native bridge. Everything below is translation only — argument
/// unpacking, JSON encoding and promise plumbing. The behaviour lives in
/// `PasspointClient` (core/swift/), which the native Swift SDK exposes directly.
///
/// There is no `import HeliumPasspoint` here: the podspec compiles the core
/// sources and this file into a single module, which is also what lets the
/// bridge reuse the core's internal `ISO8601` formatter so the timestamps
/// TypeScript receives match the ones the native SDKs produce.
@objc(HeliumPasspointSDK)
class HeliumPasspointSDK: NSObject {
  private let client = PasspointClient.shared

  @objc static func requiresMainQueueSetup() -> Bool { false }

  @objc(configure:baseUrl:eapType:serverCaCertPem:keychainAccessGroup:presetId:)
  func configure(
    _ apiKey: String,
    baseUrl: String,
    eapType: NSNumber,
    serverCaCertPem: String?,
    keychainAccessGroup: String?,
    presetId: String?
  ) {
    // The TypeScript layer has already resolved `environment` to a full URL.
    let config = PasspointConfig(
      apiKey: apiKey,
      environment: .named(baseUrl),
      eapType: EAPType(rawValue: eapType.intValue) ?? .tls,
      serverCACertificatePEM: serverCaCertPem,
      keychainAccessGroup: keychainAccessGroup,
      presetID: presetId
    )
    // configure() only rejects a blank API key, which PasspointSDK.configure()
    // in TypeScript has already refused. Swallowing here keeps the bridge
    // method void, matching the TurboModule spec.
    try? client.configure(config)
  }

  @objc(install:resolver:rejecter:)
  func install(
    _ subscriberId: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      await Self.resolveJSON(resolve, reject) {
        try await self.client.install(subscriberID: subscriberId)
        return ["success": true]
      }
    }
  }

  @objc(isInstalled:rejecter:)
  func isInstalled(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      resolve(await client.isInstalled())
    }
  }

  @objc(getCertificateInfo:rejecter:)
  func getCertificateInfo(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      await Self.resolveJSON(resolve, reject) {
        let info = await self.client.certificateInfo()
        return [
          "isInstalled": info.isInstalled,
          "expiresAt": info.expiresAt.map(ISO8601.string(from:)) ?? NSNull(),
          "subject": info.subject ?? NSNull(),
          "domain": info.domain ?? NSNull(),
          "friendlyName": info.friendlyName ?? NSNull(),
        ]
      }
    }
  }

  @objc(getRemoteStatus:resolver:rejecter:)
  func getRemoteStatus(
    _ subscriberId: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      do {
        guard let status = try await client.remoteStatus(subscriberID: subscriberId) else {
          resolve("null")
          return
        }
        resolve(
          try Self.json([
            "subscriberId": status.subscriberID,
            "presetId": status.presetID,
            "eapType": status.eapType,
            // The server's exact string, not a reformatted one — the
            // TypeScript layer surfaces it verbatim.
            "expiresAt": status.expiresAtRaw,
            "active": status.active,
          ]))
      } catch {
        Self.reject(reject, error)
      }
    }
  }

  @objc(remove:rejecter:)
  func remove(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      await Self.resolveJSON(resolve, reject) {
        try await self.client.remove()
        return ["success": true]
      }
    }
  }

  @objc(debug:rejecter:)
  func debug(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      let info = await client.diagnostics()
      // debug() must never fail — it is what support asks for when things break.
      resolve(
        (try? Self.json(info))
          ?? #"{"error":"failed to serialize diagnostics"}"#)
    }
  }

  // MARK: - Bridge plumbing

  private static func resolveJSON(
    _ resolve: @escaping RCTPromiseResolveBlock,
    _ reject: @escaping RCTPromiseRejectBlock,
    _ body: () async throws -> [String: Any]
  ) async {
    do {
      resolve(try json(await body()))
    } catch {
      self.reject(reject, error)
    }
  }

  private static func json(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PasspointError(code: .unknown, message: "Failed to encode response as UTF-8")
    }
    return string
  }

  /// Rejects with the contract error code so `PasspointError.fromNative` in
  /// TypeScript can map it back to a `PasspointErrorCode`.
  private static func reject(_ reject: RCTPromiseRejectBlock, _ error: Error) {
    if let passpointError = error as? PasspointError {
      reject(passpointError.code.rawValue, passpointError.message, passpointError)
    } else {
      reject(PasspointErrorCode.unknown.rawValue, error.localizedDescription, error)
    }
  }
}
