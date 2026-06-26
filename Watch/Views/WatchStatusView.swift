import SwiftUI
import WatchConnectivity

struct WatchStatusView: View {
    @EnvironmentObject private var sync: WatchSyncService

    var body: some View {
        let s = WCSession.default
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row("Supported", WCSession.isSupported() ? "yes" : "no")
                row("Activation", activationName(s.activationState))
                row("Companion installed", s.isCompanionAppInstalled ? "yes" : "no")
                row("Reachable", s.isReachable ? "yes" : "no")
                row("Watch bundle", Bundle.main.bundleIdentifier ?? "—")
                Divider()
                row("Files received", "\(sync.totalFilesReceived)")
                row("UserInfos received", "\(sync.totalUserInfosReceived)")
                row("Upserts processed", "\(sync.totalUpserts)")
                row("Deletes processed", "\(sync.totalDeletes)")
                row("Last received", sync.lastReceivedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "never")
                row("Last error", sync.lastError ?? "none")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .navigationTitle("Watch Status")
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .monospaced()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activationName(_ state: WCSessionActivationState) -> String {
        switch state {
        case .notActivated: return "not activated"
        case .inactive: return "inactive"
        case .activated: return "activated"
        @unknown default: return "unknown"
        }
    }
}
