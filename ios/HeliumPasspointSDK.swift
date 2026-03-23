import Foundation
import React

@objc(HeliumPasspointSDK)
class HeliumPasspointSDK: NSObject {
  private let manager = PasspointManager.shared

  @objc static func requiresMainQueueSetup() -> Bool { false }

  @objc(configure:endpoint:eapType:serverCaCertPem:keychainAccessGroup:)
  func configure(
    _ apiKey: String,
    endpoint: String,
    eapType: NSNumber,
    serverCaCertPem: String?,
    keychainAccessGroup: String?
  ) {
    manager.configure(
      apiKey: apiKey,
      endpoint: endpoint,
      eapType: eapType.intValue,
      serverCaCertPem: serverCaCertPem,
      keychainAccessGroup: keychainAccessGroup
    )
  }

  @objc(install:resolver:rejecter:)
  func install(
    _ userIdentifier: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      do {
        let result = try await manager.install(userIdentifier: userIdentifier)
        let json = try JSONSerialization.data(withJSONObject: result)
        resolve(String(data: json, encoding: .utf8))
      } catch let error as PasspointSDKError {
        reject(error.errorCode, error.localizedDescription, error)
      } catch {
        reject("UNKNOWN", error.localizedDescription, error)
      }
    }
  }

  @objc(isInstalled:rejecter:)
  func isInstalled(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      let installed = await manager.isInstalled()
      resolve(installed)
    }
  }

  @objc(getCertificateInfo:rejecter:)
  func getCertificateInfo(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      let info = await manager.getCertificateInfo()
      do {
        let json = try JSONSerialization.data(withJSONObject: info)
        resolve(String(data: json, encoding: .utf8))
      } catch {
        reject("UNKNOWN", "Failed to serialize certificate info", error)
      }
    }
  }

  @objc(debug:rejecter:)
  func debug(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      let info = await manager.debug()
      do {
        let json = try JSONSerialization.data(withJSONObject: info)
        resolve(String(data: json, encoding: .utf8))
      } catch {
        resolve("{\"error\": \"serialize failed: \(error.localizedDescription)\"}")
      }
    }
  }

  @objc(revoke:rejecter:)
  func revoke(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      do {
        let result = try await manager.revoke()
        let json = try JSONSerialization.data(withJSONObject: result)
        resolve(String(data: json, encoding: .utf8))
      } catch let error as PasspointSDKError {
        reject(error.errorCode, error.localizedDescription, error)
      } catch {
        reject("UNKNOWN", error.localizedDescription, error)
      }
    }
  }
}
