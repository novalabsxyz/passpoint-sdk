import Foundation
import HeliumPasspoint

/// Drives the example screen. Everything here uses only the SDK's public API.
@MainActor
public final class PasspointViewModel: ObservableObject {
  public enum State: Equatable {
    case unknown
    case notInstalled
    case installed(CertificateInfo)
    case working(String)
    case failed(code: PasspointErrorCode, message: String)
  }

  @Published public private(set) var state: State = .unknown
  @Published public private(set) var serverStatus: RemoteProfileStatus?

  private let client: PasspointClient
  private let subscriberID: String

  /// - Parameters:
  ///   - apiKey: partner API key issued by Helium.
  ///   - subscriberID: your own identifier for this user.
  ///   - teamID: Apple Team ID, used to build the NetworkExtension keychain
  ///     access group. Without it iOS refuses to install the profile.
  public init(apiKey: String, subscriberID: String, teamID: String) {
    self.subscriberID = subscriberID
    self.client = PasspointClient()

    do {
      try client.configure(
        PasspointConfig(
          apiKey: apiKey,
          environment: .production,
          keychainAccessGroup: "\(teamID).com.apple.networkextensionsharing"
        ))
    } catch let error as PasspointError {
      state = .failed(code: error.code, message: error.message)
    } catch {
      state = .failed(code: .unknown, message: error.localizedDescription)
    }
  }

  public func refresh() async {
    // Leave a configuration failure on screen rather than overwriting it.
    if case .failed = state { return }
    state = await client.isInstalled() ? .installed(await client.certificateInfo()) : .notInstalled
  }

  public func install() async {
    state = .working("Provisioning…")
    do {
      try await client.install(subscriberID: subscriberID)
      state = .installed(await client.certificateInfo())
    } catch {
      state = Self.failure(from: error)
    }
  }

  public func remove() async {
    state = .working("Removing…")
    do {
      try await client.remove()
      state = .notInstalled
    } catch {
      state = Self.failure(from: error)
    }
  }

  /// Reconciles with the server — catches a certificate revoked remotely while
  /// the local profile is still installed.
  public func checkServer() async {
    do {
      serverStatus = try await client.remoteStatus(subscriberID: subscriberID)
    } catch {
      state = Self.failure(from: error)
    }
  }

  /// Attach to a support ticket when something goes wrong on device.
  public func diagnostics() async -> [String: String] {
    await client.diagnostics()
  }

  private static func failure(from error: Error) -> State {
    guard let passpointError = error as? PasspointError else {
      return .failed(code: .unknown, message: error.localizedDescription)
    }
    switch passpointError.code {
    case .simulatorNotSupported:
      return .failed(code: passpointError.code, message: "Run this on a physical device.")
    case .apiUnauthorized:
      return .failed(code: passpointError.code, message: "The API key was rejected.")
    case .identityLoadFailed, .certificateSaveFailed:
      return .failed(
        code: passpointError.code,
        message: "Check the Keychain Sharing entitlement and Team ID.")
    default:
      return .failed(code: passpointError.code, message: passpointError.message)
    }
  }
}
