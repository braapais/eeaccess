import Foundation

/// Configuration for Tesla Fleet API OAuth (cloud control). These values come
/// from a registered third-party app at https://developer.tesla.com.
///
/// ⚠️ Until you register an app and fill `clientID` in, "Connect Tesla Account"
/// reports that setup is incomplete — by design, there is no way around Tesla's
/// developer registration. One-time setup:
///
///  1. Create an app at developer.tesla.com → copy the **Client ID** (and, if
///     your app is a confidential client, the **Client Secret**).
///  2. Add an **Allowed Redirect URI** that exactly matches ``redirectURI``.
///  3. Host your partner public key at
///     `https://<your-domain>/.well-known/appspecific/com.tesla.3p.public-key.pem`
///     and register the domain — required before vehicle *commands* will work.
///  4. Pick the ``audience`` host for your region (NA vs EU).
///
/// Endpoints reflect the current Fleet API: authorize on `auth.tesla.com`,
/// token exchange on `fleet-auth.prd.vn.cloud.tesla.com` (the host all
/// partners migrated to in 2025).
enum TeslaFleetConfig {
    /// From developer.tesla.com. Empty string = not configured.
    static let clientID = ""

    /// Confidential-client secret. ⚠️ Never ship a real secret in the binary —
    /// it is trivially extractable. Keep this empty (public PKCE-only client),
    /// or exchange the authorization code on a small backend you control. Only
    /// fill it in for personal/sideloaded builds.
    static let clientSecret = ""

    /// Must exactly match an Allowed Redirect URI on your Tesla app.
    ///
    /// ⚠️ Tesla's developer portal may only accept **https** redirect URIs and
    /// reject custom schemes. If registration refuses this value, switch to an
    /// https URL on a domain you own and replace the session's
    /// `callbackURLScheme` in `TeslaFleetAuth.authenticate(url:)` with
    /// `ASWebAuthenticationSession.Callback.https(host:path:)` (requires the
    /// matching universal-link / associated-domain setup).
    static let redirectURI = "eeaccess://tesla/callback"

    /// The custom URL-scheme portion of ``redirectURI`` handed to the auth
    /// session as its callback scheme.
    static let callbackScheme = "eeaccess"

    /// Region API base ("audience"). North America shown; use
    /// `https://fleet-api.prd.eu.vn.cloud.tesla.com` in Europe.
    static let audience = "https://fleet-api.prd.na.vn.cloud.tesla.com"

    /// Base URL for *commands* (lock/unlock/climate). 2021+ vehicles (incl.
    /// the 2023 Model X) reject unsigned commands, so these must be signed by
    /// Tesla's `tesla-http-proxy` using the public key enrolled in the car.
    /// Point this at your running proxy (e.g. "https://your-host:4443") to
    /// enable cloud commands. Left equal to ``audience``, reading state and
    /// waking work, but lock/unlock/climate return "Vehicle Command Protocol
    /// required". Pre-2021 S/X can use ``audience`` directly.
    static let commandBaseURL = audience

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
