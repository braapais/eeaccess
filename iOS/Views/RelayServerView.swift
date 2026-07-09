import SwiftUI

/// Settings for the optional self-hosted relay server. When on, cloud commands
/// go through your server, and Unlock+Drive can be scheduled server-side so it
/// fires even when the phone/watch is offline in a garage.
struct RelayServerView: View {
    @Environment(RelayServerClient.self) private var relay
    @EnvironmentObject private var sync: PhoneSyncService

    private let store = RelayServerStore()

    @State private var enabled = false
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var saved = false
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                Text("Route cloud commands through your own server instead of Tesla directly. The point: a scheduled Unlock+Drive runs on the server, so it fires even when your phone or watch has no signal in a garage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Server") {
                Toggle("Use my server", isOn: $enabled)
                TextField("URL (https://…)", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section {
                Button("Save") { save() }
                Button("Test connection") { Task { await test() } }
                    .disabled(baseURL.isEmpty || username.isEmpty)
                if testing { HStack { ProgressView(); Text("Testing…") } }
                if let testResult {
                    Text(testResult).font(.footnote)
                        .foregroundStyle(testResult.hasPrefix("✅") ? .green : .red)
                }
                if saved { Text("Saved").font(.footnote).foregroundStyle(.green) }
            }
        }
        .navigationTitle("Relay Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        enabled = store.enabled
        baseURL = store.baseURL
        username = store.username
        password = store.password
    }
    private func save() {
        store.baseURL = baseURL
        store.username = username
        store.password = password
        store.enabled = enabled
        relay.reloadSettings()
        sync.sendRelaySettings(enabled: enabled, baseURL: store.baseURL, username: username, password: password)
        saved = true
    }
    private func test() async {
        save()
        testing = true
        testResult = nil
        defer { testing = false }
        await relay.fetchVehicles()
        if let err = relay.lastError {
            testResult = "❌ \(err)"
        } else {
            testResult = "✅ Connected — \(relay.accountVehicles.count) vehicle(s)"
        }
    }
}
