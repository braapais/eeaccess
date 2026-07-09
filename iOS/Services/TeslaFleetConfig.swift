import Foundation

/// Configuration for Tesla Fleet API OAuth (cloud control).
///
/// **Bring-your-own-credentials:** rather than shipping a shared Client ID
/// (which would bill every user's Fleet API usage to the developer and require
/// a backend for the secret), each user registers their own app at
/// developer.tesla.com and enters its Client ID in the app — stored in
/// ``TeslaFleetCredentialsStore``. Until they do, "Connect Tesla Account"
/// reports that setup is incomplete.
///
/// One-time setup for a user (surfaced in the in-app credentials screen):
///  1. Create an app at developer.tesla.com → copy the **Client ID** (and, if
///     it's a confidential client, the **Client Secret**).
///  2. Add an **Allowed Redirect URI** matching ``redirectURI``.
///  3. Host their partner public key at
///     `https://<domain>/.well-known/appspecific/com.tesla.3p.public-key.pem`
///     and register the domain — required before vehicle *commands* work.
///  4. Pick their region (NA vs EU).
///
/// Endpoints reflect the current Fleet API: authorize on `auth.tesla.com`,
/// token exchange on `fleet-auth.prd.vn.cloud.tesla.com`.
enum TeslaFleetConfig {
    /// User-provided credentials (Client ID / secret / region / redirect).
    static let store = TeslaFleetCredentialsStore()

    /// Optional compile-time fallbacks. The public build ships these empty so
    /// users bring their own; a personal/sideloaded build may hardcode them.
    private static let fallbackClientID = ""
    private static let fallbackClientSecret = ""

    /// From the user's developer.tesla.com app. Empty = not configured.
    static var clientID: String {
        let v = store.clientID
        return v.isEmpty ? fallbackClientID : v
    }

    /// Confidential-client secret. For bring-your-own it's the user's *own*
    /// secret, kept in their device Keychain — never shipped in the binary.
    /// Leave empty for a public (PKCE-only) client.
    static var clientSecret: String {
        let v = store.clientSecret
        return v.isEmpty ? fallbackClientSecret : v
    }

    /// Must exactly match an Allowed Redirect URI on the user's Tesla app.
    /// Defaults to the app's custom scheme; a user whose Tesla app requires an
    /// https redirect can enter their own bounce URL (a static page that
    /// redirects to `eeaccess://tesla/callback` — see BrandAssets/tesla docs).
    static var redirectURI: String {
        let v = store.redirectURI
        return v.isEmpty ? "eeaccess://tesla/callback" : v
    }

    /// The custom URL-scheme the auth session watches for. Fixed to the app's
    /// scheme regardless of the registered redirect (an https redirect must
    /// bounce back to this scheme).
    static let callbackScheme = "eeaccess"

    /// Region API base ("audience"), from the user's selection.
    static var audience: String { store.region.audience }

    /// Base URL for *commands*. Pre-2021 S/X accept unsigned commands, so they
    /// go to ``audience`` directly (via the service's `unsigned:` flag). 2021+
    /// cars would need a signing proxy — out of scope for bring-your-own.
    static var commandBaseURL: String { audience }

    static let authorizeURL = URL(string: "https://auth.tesla.com/oauth2/v3/authorize")!
    static let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!

    /// Scopes for the key feature: identity, a refresh token, read state, and
    /// vehicle/charging commands.
    static let scopes = [
        "openid",
        "offline_access",
        "vehicle_device_data",
        "vehicle_cmds",
        "vehicle_charging_cmds",
    ]

    static var isConfigured: Bool { !clientID.isEmpty }
}
