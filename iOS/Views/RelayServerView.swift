import SwiftUI

/// Settings for the shared, built-in EEAccess relay. No server URL, username,
/// or password to enter — tap Connect, sign into Tesla, and the relay
/// auto-provisions this device an API key. When on, cloud commands go through
/// the relay, and Unlock+Drive can be scheduled server-side so it fires even
/// when the phone/watch is offline in a garage.
struct RelayServerView: View {
    @Environment(RelayServerClient.self) private var relay
    @Environment(RelayAuth.self) private var auth
    @EnvironmentObject private var sync: PhoneSyncService

    @State private var enabled = false

    var body: some View {
        Form {
            Section {
                Text("Route cloud commands through EEAccess's relay instead of Tesla directly. The point: a scheduled Unlock+Drive runs on the server, so it fires even when your phone or watch has no signal in a garage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Tesla account") {
                if relay.store.isActive {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Toggle("Use the relay", isOn: $enabled)
                        .onChange(of: enabled) { _, newValue in
                            relay.store.enabled = newValue
                            relay.reloadSettings()
                            sync.sendRelaySettings(enabled: newValue, apiKey: relay.store.apiKey)
                        }
                    Button(role: .destructive) {
                        Task {
                            await relay.disconnect()
                            sync.sendRelaySettings(enabled: false, apiKey: "")
                            enabled = false
                        }
                    } label: {
                        Label("Disconnect", systemImage: "person.badge.minus")
                    }
                    Text("Disconnect deletes your Tesla session from the relay.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    switch auth.status {
                    case .idle, .failed:
                        Button {
                            Task {
                                await auth.connect(relay: relay)
                                enabled = relay.store.enabled
                                sync.sendRelaySettings(enabled: relay.store.enabled, apiKey: relay.store.apiKey)
                            }
                        } label: {
                            Label("Connect Tesla Account", systemImage: "person.badge.key")
                        }
                        if case let .failed(message) = auth.status {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                    case .connecting:
                        HStack { ProgressView(); Text("Connecting…") }
                    }
                }
            }
        }
        .navigationTitle("Relay")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { enabled = relay.store.enabled }
    }
}
