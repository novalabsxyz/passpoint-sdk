import HeliumPasspoint
import SwiftUI

/// Drop into any SwiftUI app:
///
/// ```swift
/// PasspointScreen(apiKey: "…", subscriberID: "user-123", teamID: "ABCDE12345")
/// ```
public struct PasspointScreen: View {
  @StateObject private var model: PasspointViewModel

  public init(apiKey: String, subscriberID: String, teamID: String) {
    _model = StateObject(
      wrappedValue: PasspointViewModel(
        apiKey: apiKey, subscriberID: subscriberID, teamID: teamID))
  }

  public var body: some View {
    List {
      Section("Status") {
        switch model.state {
        case .unknown:
          Text("Checking…").foregroundStyle(.secondary)
        case .notInstalled:
          Text("No Helium profile installed")
        case .working(let message):
          HStack { ProgressView(); Text(message) }
        case .installed(let info):
          row("Network", info.friendlyName ?? "Helium")
          row("Domain", info.domain ?? "—")
          row("Expires", info.expiresAt.map(Self.format) ?? "—")
        case .failed(let code, let message):
          VStack(alignment: .leading, spacing: 4) {
            Text(code.rawValue).font(.caption.monospaced()).foregroundStyle(.red)
            Text(message).font(.footnote)
          }
        }
      }

      if let status = model.serverStatus {
        Section("Server") {
          row("Active", status.active ? "yes" : "no")
          // expiresAt is nil when the server sends a timestamp the SDK cannot
          // parse; expiresAtRaw always carries the server's exact string.
          row("Expires", status.expiresAt.map(Self.format) ?? status.expiresAtRaw)
        }
      }

      Section {
        Button("Install profile") { Task { await model.install() } }
        Button("Check server status") { Task { await model.checkServer() } }
        Button("Remove profile", role: .destructive) { Task { await model.remove() } }
      }
    }
    .task { await model.refresh() }
  }

  /// `LabeledContent` is iOS 16+; the SDK supports iOS 15, so the example does too.
  private func row(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value).foregroundStyle(.secondary)
    }
  }

  private static func format(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
