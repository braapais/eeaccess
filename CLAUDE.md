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
locally so no registry access is needed). Pick a **release** Xcode (26.x) in the
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
  running `tesla-http-proxy` for 2021+ signed cars).
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
  proxy). The watch has no Fleet client — cloud cars show a "control from
  iPhone" screen there, no pairing. Still needs the Client ID + partner domain
  registration to function.
- **Phone↔watch:** VIN/name/role sync over WatchConnectivity
  (`tesla-upsert`/`tesla-delete` file transfers). Watch preserves `isPaired`
  and (once paired) `keyRoleRaw` — the role is baked into the enrolled key.
- **Multiple vehicles:** `TeslaVehicle` records are keyed by VIN (unique); the
  app supports more than one car. iPhone: `TeslaKeySettingsView` lists vehicles
  → `TeslaVehicleFormView` add/edit each; **cloud commands are per-car** in that
  view (Refresh/Wake/Lock/Unlock/Start Drive/Climate, shown when signed in;
  Start Drive = Fleet `remote_start_drive`), not a global section. Add Vehicle imports the signed-in account's cars
  (`TeslaFleetService.fetchVehicles` → `GET /api/1/vehicles`) so the VIN is
  picked, not typed. Watch: `WatchTeslaKeyView` routes none→setup / one→direct /
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
