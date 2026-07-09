import SwiftUI

/// In-app walkthrough for obtaining Tesla Fleet API credentials, shown from
/// the credentials screen. Cloud control is bring-your-own, so users need a
/// clear path to their own Client ID.
struct TeslaCredentialsHelpView: View {
    var body: some View {
        List {
            Section {
                Text("Cloud control (for cars without the Apple Watch Bluetooth key — like pre-2021 Model S/X) uses your own free Tesla developer app. It's an advanced, ~15-minute setup. If your car supports the Bluetooth key (Model 3/Y, Cybertruck, 2021+ S/X), you don't need any of this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("1 · Create a developer app") {
                step("Go to developer.tesla.com and sign in with your Tesla account.")
                step("Create a new application. Give it a name and enter a website/domain you control.")
                Link("Open developer.tesla.com", destination: URL(string: "https://developer.tesla.com")!)
            }

            Section("2 · Set the OAuth details") {
                step("Allowed Redirect URI: enter eeaccess://tesla/callback. If Tesla only accepts an https address, enter your own https “bounce” URL instead and put that same value in the Redirect URI field.")
                step("Scopes: enable vehicle information and vehicle commands (plus offline access).")
            }

            Section("3 · Copy your Client ID") {
                step("After the app is created, copy the Client ID — and the Client Secret if one is shown.")
                step("Paste them on the previous screen, then pick your region (Europe or North America).")
            }

            Section("4 · Authorize commands (host a key)") {
                step("Tesla requires you to host a public key at https://<your-domain>/.well-known/appspecific/com.tesla.3p.public-key.pem and register that domain. Lock/unlock won’t work until this is done.")
                step("A free static host (e.g. GitHub Pages) works. Follow Tesla’s Fleet API guide for the exact commands.")
                Link("Tesla Fleet API docs", destination: URL(string: "https://developer.tesla.com/docs/fleet-api")!)
            }

            Section {
                Text("Tesla’s Fleet API has a monthly free allowance that usually covers personal use; you may be asked to add a payment method. Your credentials stay on this device — the Client Secret is kept in the Keychain and is never shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("How to get credentials")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
    }
}
