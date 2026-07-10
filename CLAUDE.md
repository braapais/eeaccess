# CLAUDE.md — EEAccess

iOS + standalone Apple Watch app: loyalty-card wallet **plus a Tesla BLE car
key on the watch** (lock/unlock/drive a 2023 Model X with no phone, no
internet, no Tesla account).

## Hard rules

1. **`project.yml` is the source of truth** (XcodeGen). Never edit
   `EEAccess.xcodeproj` by hand and never add files through Xcode's UI — add
   them on disk in the right folder, then run `xcodegen generate`.
2. **After every change set:** update the docs (this file, `README.md`,
   `OVERVIEW.md` as relevant) **and bump the version** in `project.yml` —
   `CURRENT_PROJECT_VERSION` every time (App Store Connect rejects duplicate
   build numbers), `MARKETING_VERSION` for release-worthy features. Then
   `xcodegen generate` and verify both schemes still build.
3. Versions, signing team, bundle IDs all live in `project.yml`; anything set
   in Xcode's UI is lost on the next regenerate.

## Build & verify

```bash
xcodegen generate   # after project.yml or file-layout changes

xcodebuild -project EEAccess.xcodeproj -scheme EEAccess \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project EEAccess.xcodeproj -scheme EEAccessWatchApp \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

cd TeslaKeyKit && swift test   # 184 protocol/crypto tests, no hardware needed
```

## Releasing (git + Xcode Cloud)

Now a git repo. The dev Mac is on **macOS 27 beta**, and App Store Connect
rejects builds produced on a beta OS (ITMS-90111) even with the correct SDK —
so release builds go through **Xcode Cloud** (Apple's release macOS/Xcode).
`ci_scripts/ci_post_clone.sh` installs XcodeGen and regenerates the project on
each Cloud build (`EEAccess.xcodeproj` is git-ignored; packages are vendored
locally so no registry access is needed). `brew install xcodegen` retries once
after `brew update` if it fails — Xcode Cloud's Homebrew snapshot can be stale
enough that xcodegen isn't in the local formula index yet (broke a build once).
Pick a **release** Xcode (26.x) in the
workflow, never a beta. Full steps: `BrandAssets/XCODE_CLOUD_SETUP.md`. Local
Xcode 26.5 GUI won't `open`-launch on the beta macOS (LS error -10664) — run the
binary directly: `/Applications/Xcode.app/Contents/MacOS/Xcode &`.

## Targets (all versioned together via settings.base)

| Target | Bundle ID | Notes |
|---|---|---|
| EEAccess (iOS) | com.elbaeverywhere.eeaccess | embeds the rest |
| EEAccessWatchApp | …eeaccess.watchkitapp | standalone watch app |
| EEAccessComplication | …eeaccess.watchkitapp.carkey | WidgetKit; ID was renamed from `.complication` (unregisterable) — don't rename back |
| EEAccessShareExtension | …eeaccess.share | |

Team `325KTS65QS`, automatic signing. Deployment targets iOS 26 / watchOS 26.

## Tesla key architecture (the short version)

- **`TeslaKeyKit/`** — vendored fork of `shoujiaxin/swift-tesla-ble` (MIT),
  local SPM package, product `TeslaBLE`, watch target only. Only local change:
  `.watchOS(.v10)` added to platforms. Tesla VCSEC protocol, CryptoKit P-256 +
  AES-GCM, protobuf. Don't reimplement protocol bits — they're in here.
- **`Vendor/swift-protobuf/`** — trimmed local copy of swift-protobuf 1.38.0
  (runtime `SwiftProtobuf` library only), referenced by TeslaKeyKit via
  `.package(path:)`. Vendored because upstream declares **no** `platforms`, so
  Xcode builds it at watchOS 8.0 — below the 9.0 floor of current watchOS SDKs
  — and `archive` fails. The local manifest adds `platforms` (watchOS 10).
  Don't re-point TeslaKeyKit at the remote swift-protobuf, and keep the
  `platforms:` line, or archiving breaks again.
- **BLE key (watch, no account):** `Watch/Services/TeslaKeyService.swift`
  wraps `TeslaVehicleClient` (one actor per VIN). Private key: watch Keychain,
  device-only, per-VIN, survives reinstall. Pairing = unsigned `addKey` over a
  `.pairing`-mode connection → user taps physical key card on console →
  Confirm on car screen → reconnect normal to verify. **Gotcha:** a pairing
  link reports `.connected` but has no signed sessions — `isPairingConnection`
  flag + `usableClient(vin:)` exist to handle exactly that; keep them.
- **Presence auto-entry:** `TeslaPresenceScanner` matches the VIN-derived BLE
  local name (`"S"+hex(sha1(VIN)[0..8])+"C"`); nil-service scans don't run in
  background on watchOS, so enter/leave transitions are gated on app-active
  (`setAppActive` from scenePhase) — background "loss" is throttling, not
  distance. Auto-unlock deliberately requires the app frontmost. **Two scan
  gotchas (both bit us):** the scan must run with
  `CBCentralManagerScanOptionAllowDuplicatesKey: true` — with filtering on,
  CoreBluetooth reports the car ONCE per scan session, so approach RSSI never
  updates and auto-unlock only fires on lucky timing; and the car stops
  advertising while a BLE link is open, so the loss timer must treat a live
  connection as "near" (`presence.hasLiveConnection`) or it fires a phantom
  auto-lock right after auto-unlock.
- **Drive:** watch key presence alone may not arm drive-away; `startDrive(vin:)`
  sends `.security(.remoteDrive)` (`RKE_ACTION_REMOTE_DRIVE` — the Tesla app's
  Keyless Driving): car allows driving for ~2 min, press brake within window.
- **Lock/unlock are status-gated:** both read the VCSEC lock state first
  (`client.query(.bodyControllerState)` → `vehicleLockState`, 3 s timeout, via
  `lockState(client:)`) and skip the command when the car is already in the
  target state ("Already locked/unlocked"). If the state can't be read they act
  anyway, so the buttons never dead-end. Auto-unlock/-lock reuse the same paths,
  so proximity re-entries don't re-fire either.
- **Cloud (iOS, optional):** `TeslaFleetAuth` (OAuth PKCE) + `TeslaFleetService`
  (state/wake direct; lock/unlock/climate need `commandBaseURL` pointed at a
  running `tesla-http-proxy` for 2021+ signed cars). **Wake polls after the
  request**: `wake_up` only asks Tesla to wake the car (can take up to ~30s),
  so `wake()` follows up with `pollUntilAwake` — 3s-interval `vehicle_data`
  polls (up to ~10, swallowing the expected 408s while still asleep) — instead
  of a flat "Done" that looks like nothing happened. Same pattern in
  `WatchTeslaCloud.wake` and `RelayServerClient.wake`. **Immediate combo:**
  `unlockAndDrive(vin:)` on all three clients sends Unlock then Start Drive
  back-to-back with no delay (the "Unlock & Drive" button) — distinct from the
  scheduled version, which is for triggering ahead of time before losing
  signal.
- **Bring-your-own credentials:** the Fleet Client ID is NOT shipped — each
  user registers their own developer.tesla.com app and enters the Client ID
  (+ optional secret, region, redirect URI) in `TeslaCredentialsView`, persisted
  in `TeslaFleetCredentialsStore` (secret in Keychain, rest in UserDefaults).
  `TeslaFleetConfig` reads through the store (empty = honest "Not configured");
  `TeslaFleetAuth.reloadConfiguration()` refreshes status after edits. This
  keeps per-user API costs on the user and no shared secret in the binary.
- **Cloud-only vehicles (pre-2021 S/X):** `TeslaVehicle.accessMode`
  (`bluetoothKey` | `cloud`, synced phone→watch in the `tesla-upsert` payload).
  Pre-2021 Model S/X have **no BLE phone key**, so they're `cloud` mode:
  controlled from the iPhone via Fleet API using Tesla-account OAuth. Tesla
  **exempts pre-2021 S/X from signed commands**, so `TeslaFleetService`'s
  `unsigned:` flag sends lock/unlock/climate straight to the Fleet host (no
  proxy). On the **watch**, cloud cars get their own controls via
  `WatchTeslaCloud` (a lightweight Fleet client) using the access token + region
  host the iPhone syncs over WatchConnectivity **application context**
  (`PhoneSyncService.sendTeslaCloudSession`, pushed by
  `EEAccessApp.syncTeslaSession` on launch/active; applied in `WatchSyncService`
  → `WatchTeslaCloud.applySession`). The phone also syncs the **refresh token +
  Client ID/secret**, so the watch refreshes the access token itself directly
  against Tesla's token endpoint over LTE/WiFi (`WatchTeslaCloud.ensureFreshToken`
  on app-active + before each command) — fully phone-independent once synced;
  it only asks to reopen the iPhone if the refresh token is revoked. Those
  secrets live device-only (synced over the encrypted WC channel). Still needs
  the Client ID + partner domain registration to function.
- **Garage dead-zone (scheduled unlock+drive):** `scheduleUnlockDrive(vin:…,
  delay: 60)` on both `TeslaFleetService` (phone) and `WatchTeslaCloud` (watch)
  counts down then sends Unlock + Start Drive (retries 3× if the network blips)
  — trigger it while you still have signal so the car is ready when you reach a
  no-signal garage. `scheduledSeconds` drives the live countdown/cancel UI; runs
  only while the app is foregrounded (no background execution guarantee).
- **Relay server (phase 3, `Shared/RelayServer.swift` + `iOS/Services/RelayAuth.swift`
  + `server/`):** a shared, centrally-hosted, **multi-tenant** Node relay
  (`https://eeaccess.elbaeverywhere.com`, nginx TLS in front of `127.0.0.1:8737`
  on the tailnet box) — built-in, available to every user, no server to run.
  One shared Tesla Developer app (`server/config.json`'s `clientId`/`clientSecret`)
  so users never register their own, but each user gets their own Tesla OAuth
  session — own refresh token, own vehicles — in their own `server/users/<uuid>.json`.
  **No username or password anywhere**: `RelayAuth` (iOS-only —
  `ASWebAuthenticationSession`, watchOS has none) drives a server-mediated
  OAuth dance (`GET /oauth/start` → Tesla login → Tesla redirects to the
  *server's* `/oauth/callback`, not the app, so the shared Client Secret never
  reaches the binary → a bounce page hands `code`+`state` to the app via
  `eeaccess://tesla/relay-callback` → app posts `POST /oauth/complete` → server
  does the real exchange and returns a random per-user **API key**, auto-
  provisioned, stored in Keychain via `RelayServerStore`). `RelayServerClient`
  (@Observable, in `Shared/`) sends that key as `Authorization: Bearer` and
  works unmodified on both platforms. Every `vin`-scoped server request
  verifies the VIN actually belongs to the caller's own Tesla account
  (`assertOwnsVehicle`, refreshed from Tesla if not cached) so one user can't
  steer commands at another user's car; requests are rate-limited per user
  (30/min) to bound the blast radius of a runaway client against the shared
  Tesla app's standing — **Tesla scopes suspension to the whole Client ID, not
  the offending user**, so a limit here protects everyone, including this
  app's own cars. `DELETE /account` self-service-deletes a user's server-side
  data (works even while rate-limited — the escape hatch a stuck client
  needs). When active (`relay.isActive`), iOS per-car cloud controls route
  through it (`RelayServerView` — Connect/Disconnect only, nothing to type),
  and `scheduleUnlockDrive` runs **server-side** (`POST /vehicles/:vin/schedule`)
  so it fires even if the device goes offline in a garage. Settings sync
  phone→watch is now just `{enabled, apiKey}` (`PhoneSyncService.sendRelaySettings`
  file transfer → `WatchSyncService` writes `RelayServerStore`, bumps
  `relaySettingsVersion` → `reloadSettings()`); the watch's cloud car routes
  through the relay too (`WatchTeslaVehicleView.relayControls`) — simpler than
  the direct token-sync path (no refresh logic needed on the watch at all, the
  relay handles it). Relay only ever sends **unsigned** commands, so it's
  gated to `.cloud`-mode vehicles on both iOS (`useRelay = relay.isActive &&
  vehicle.accessMode == .cloud`) and watch (cloud screen only reachable for
  `.cloud` cars) — a 2021+ car always falls back to the direct signed/unsigned-
  aware `TeslaFleetService` path so a signing-required failure is visible, not
  a silently-dropped schedule. Schedules are per-user+VIN and **persisted
  server-side** (`server/schedules.json`) so a pending Unlock+Drive survives a
  service restart — re-armed on boot, fired immediately if overdue within a
  15-min grace window. Server auth uses constant-time comparison
  (`timingSafeEqual`) and forwards Tesla's real upstream status (e.g. 408 =
  asleep, 403 = not your car) instead of flattening every failure to 502.
  **Setup dependency:** the shared Tesla app must have
  `https://eeaccess.elbaeverywhere.com/oauth/callback` registered as an
  Allowed Redirect URI at developer.tesla.com (manual, one-time, in addition
  to the existing `braapais.github.io/tesla/manual/` redirect used for the
  developer's own original single-tenant setup).
- **Phone↔watch:** VIN/name/role sync over WatchConnectivity
  (`tesla-upsert`/`tesla-delete` file transfers). Watch preserves `isPaired`
  and (once paired) `keyRoleRaw` — the role is baked into the enrolled key.
- **Multiple vehicles:** `TeslaVehicle` records are keyed by VIN (unique); the
  app supports more than one car. iPhone: `TeslaKeySettingsView` lists vehicles
  → `TeslaVehicleFormView` add/edit each; **cloud commands are per-car** in that
  view (Refresh/Wake/Unlock/Lock/Start Drive/**Unlock & Drive**/Climate, shown
  when signed in), not a global section. Add Vehicle imports the connected
  account's cars — checks the **relay first, then direct BYOC**
  (`accountVehicles` picks whichever is active; either source needs a
  registered/connected Tesla session) — so the VIN is picked, not typed, and
  the display name comes straight from Tesla. Editing an existing vehicle also
  has a standalone **"Get name from Tesla"** button (`importNameFromTesla`) to
  pull the real name in later without re-adding the car; the Name field is
  otherwise a plain editable rename. Watch: `WatchTeslaKeyView` routes none→setup / one→direct /
  many→list, with per-car controls in `WatchTeslaVehicleView`;
  `WatchPairingView(vehicle:)` pairs a specific car (nil = add new). One BLE
  connection and one `TeslaPresenceScanner` are active at a time (the car whose
  screen is open) — simultaneous multi-car presence isn't attempted.

## Other conventions

- SwiftUI + SwiftData; services are `@MainActor @Observable` (newer) or
  `ObservableObject` (older — don't churn them).
- Paywall: 14-day trial then one-time IAP (`EntitlementManager`). Unlock paths:
  `isPurchased` (IAP) · `isComped` (in-app access code) · `isInTrial` ·
  `isSandboxBuild` (TestFlight/review) · `#if DEBUG` (Xcode runs). Keep all of
  these. **In-app access codes:** free comps redeemed via the "Redeem Code"
  field (Apple offer/custom codes only work for subscriptions, and this app is a
  non-consumable). Valid codes are stored as SHA-256 hashes in
  `EntitlementManager.validCodeHashes`; add one with
  `printf '%s' "CODE" | shasum -a 256`.
- Watch barcode images are pre-rendered on iOS (CoreImage doesn't exist on
  watchOS).
- Real-car testing is the only way to validate BLE flows; simulators can't do
  vehicle BLE. Fleet API cloud commands additionally need the Tesla dev
  account + proxy.
