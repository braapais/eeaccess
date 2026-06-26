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
  distance. Auto-unlock deliberately requires the app frontmost.
- **Cloud (iOS, optional):** `TeslaFleetAuth` (OAuth PKCE; needs a
  developer.tesla.com Client ID in `TeslaFleetConfig` — empty = honest "Not
  configured") + `TeslaFleetService` (state/wake direct; lock/unlock/climate
  need `commandBaseURL` pointed at a running `tesla-http-proxy`, because
  2021+ vehicles reject unsigned commands).
- **Phone↔watch:** VIN/name/role sync over WatchConnectivity
  (`tesla-upsert`/`tesla-delete` file transfers). Watch preserves `isPaired`
  and (once paired) `keyRoleRaw` — the role is baked into the enrolled key.

## Other conventions

- SwiftUI + SwiftData; services are `@MainActor @Observable` (newer) or
  `ObservableObject` (older — don't churn them).
- Paywall: 14-day trial then one-time IAP (`EntitlementManager`). TestFlight /
  review builds bypass it via the sandbox-receipt check — keep that.
- Watch barcode images are pre-rendered on iOS (CoreImage doesn't exist on
  watchOS).
- Real-car testing is the only way to validate BLE flows; simulators can't do
  vehicle BLE. Fleet API cloud commands additionally need the Tesla dev
  account + proxy.
