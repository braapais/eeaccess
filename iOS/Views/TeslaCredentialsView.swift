import SwiftUI

/// Bring-your-own Tesla Fleet API credentials. The user registers their own
/// app at developer.tesla.com and enters its Client ID here, so their API
/// usage is billed to them (not the developer) and no shared secret ships.
struct TeslaCredentialsView: View {
    @Environment(TeslaFleetAuth.self) private var fleetAuth

    private let store = TeslaFleetConfig.store

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var region: TeslaRegion = .eu
    @State private var redirectURI = ""
    @State private var saved = false

    private var trimmedID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Text("Cloud control uses your own Tesla developer app, so your API usage is billed to you — not shared. Create one at developer.tesla.com, then paste its Client ID below. The Apple Watch Bluetooth key needs none of this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    TeslaCredentialsHelpView()
                } label: {
                    Label("How do I get these?", systemImage: "questionmark.circle")
                }
                Link("Open developer.tesla.com", destination: URL(string: "https://developer.tesla.com")!)
            }

            Section("Credentials") {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Client Secret (optional)", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Region", selection: $region) {
                    ForEach(TeslaRegion.allCases, id: \.self) { r in
                        Text(r.title).tag(r)
                    }
                }
            }

            Section("Redirect URI") {
                TextField("Redirect URI", text: $redirectURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Must exactly match an Allowed Redirect URI on your Tesla app. Keep eeaccess://tesla/callback unless Tesla required an https URL — then enter your bounce URL (a static page that redirects to eeaccess://tesla/callback).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save") { save() }
                    .disabled(trimmedID.isEmpty)
                if saved {
                    Label("Saved — Connect Tesla Account back on the previous screen.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if !store.clientID.isEmpty {
                    Button("Clear credentials", role: .destructive) { clearCreds() }
                }
            }
        }
        .navigationTitle("Tesla API Credentials")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        clientID = store.clientID
        clientSecret = store.clientSecret
        region = store.region
        let saved = store.redirectURI
        redirectURI = saved.isEmpty ? "eeaccess://tesla/callback" : saved
    }

    private func save() {
        store.clientID = clientID
        store.clientSecret = clientSecret
        store.region = region
        store.redirectURI = redirectURI
        fleetAuth.reloadConfiguration()
        saved = true
    }

    private func clearCreds() {
        store.clear()
        clientID = ""
        clientSecret = ""
        redirectURI = "eeaccess://tesla/callback"
        fleetAuth.reloadConfiguration()
        saved = false
    }
}
