# EEAccess

A simple iOS + Apple Watch wallet for loyalty cards, gym membership QR codes,
and any scannable card — **plus a Tesla Bluetooth car key on the watch**
(lock, unlock, and drive without phone, internet, or Tesla account). The
watch app is **independent** — it works without the iPhone nearby once cards
have been synced.

## Project layout

```
project.yml                      → XcodeGen spec (single source of truth for targets)
EEAccess.xcodeproj               → generated, do NOT edit by hand
CLAUDE.md                        → working conventions (versioning, build, architecture)

TeslaKeyKit/                     → vendored swift-tesla-ble (MIT), local SPM package
                                   "TeslaBLE" — Tesla VCSEC BLE protocol, CryptoKit
                                   crypto, protobuf. Watch target only. 184 tests.
Vendor/swift-protobuf/           → trimmed local swift-protobuf 1.38.0 (runtime only);
                                   adds a platforms: declaration so it builds at
                                   watchOS 10 (upstream has none → archive fails on
                                   watchOS 9.0+ SDKs). Referenced by TeslaKeyKit via path.

Shared/                          → in BOTH app targets
  Card.swift                       SwiftData model (cards)
  TeslaVehicle.swift               SwiftData model (paired Tesla: VIN/name/role/state)
  CardPayload.swift                Codable transfer struct
  CardOrdering.swift               recently-used ordering helpers
  ColorHex.swift                   Color(hex:) helper
  AppGroup.swift / PendingShare.swift  share-extension plumbing

iOS/                             → iOS target only
  EEAccessApp.swift                @main entry, ModelContainer wiring
  Views/CardListView.swift         Wallet list (toolbar: Tesla Key icon → setup)
  Views/CardDetailView.swift       Fullscreen barcode display
  Views/AddCardView.swift          Add card (camera scan, photo upload, paste, manual)
  Views/TeslaKeySettingsView.swift Tesla: VIN entry + sync, account OAuth, cloud control
  Views/PaywallView.swift          Trial/one-time-unlock paywall (+ Redeem Code)
  Views/ScannerView.swift / LogoCropView.swift / CardRowView.swift
  Services/PhoneSyncService.swift  WatchConnectivity (cards + Tesla vehicle sync)
  Services/TeslaFleetConfig.swift  Fleet API endpoints/Client ID/redirect (fill to enable)
  Services/TeslaFleetAuth.swift    Tesla OAuth (PKCE), tokens in Keychain
  Services/TeslaFleetService.swift Fleet API REST: state, wake, lock/unlock, climate
  Services/EntitlementManager.swift  StoreKit 2 trial/purchase gate
  Services/BarcodeRenderer.swift / BarcodeDecoder.swift / AppStoreSearchService.swift / ShareInbox.swift
  Extensions/UIImage+Resize.swift / ImageProcessing.swift

Watch/                           → watchOS target only
  EEAccessWatchApp.swift           @main entry (cards + Tesla containers, key service)
  Views/WatchCardListView.swift    Wallet list (+ "Tesla Key" row, complication deep link)
  Views/WatchCardDetailView.swift  Barcode/image display (no rendering)
  Views/WatchTeslaKeyView.swift    Lock / Unlock / Connect-to-drive + auto-entry toggle
  Views/WatchPairingView.swift     In-car pairing wizard + key management
  Views/WatchStatusView.swift      Sync diagnostics
  Services/WatchSyncService.swift  WatchConnectivity (cards + Tesla vehicle sync)
  Services/TeslaKeyService.swift   BLE key: pair, verify, lock/unlock/drive
  Services/TeslaPresenceScanner.swift  Presence (auto-unlock/lock, app-active gated)

WatchComplication/               → WidgetKit complication ("Tesla Key" on the watch face,
                                   deep-links to WatchTeslaKeyView)
ShareExtension/                  → iOS share extension

_xcode_backup_*/                 → snapshot of the earlier Xcode-template
                                   project; safe to delete
```

## Day-to-day workflow

```bash
# After editing project.yml or adding/moving Swift files:
xcodegen generate

# Build & test from the terminal:
xcodebuild -project EEAccess.xcodeproj -scheme EEAccess \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project EEAccess.xcodeproj -scheme EEAccessWatchApp \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

For day-to-day editing just open `EEAccess.xcodeproj` in Xcode — it builds
fine. **Don't add files through Xcode's UI** — add them to the right
folder on disk and run `xcodegen generate`. That way target membership is
always correct and you can never reproduce the original "everything in
both targets" bug.

## How sync works

- iPhone → Watch only (v1). Adding or deleting on iPhone sends one
  `WCSession.transferUserInfo` payload (queued, delivered when watch is
  reachable, survives restarts).
- The barcode is rendered to PNG **on iOS at save time** and stored in
  `Card.barcodeImageData`. Why: CoreImage barcode generators (`CIQRCodeGenerator`,
  `CICode128BarcodeGenerator`, etc.) are not available on watchOS. The watch
  receives the PNG and just displays it — no rendering needed.
- Each payload also includes the optional uploaded image (JPEG-compressed
  to ≤1024px) and the raw barcode value.
- Watch persists locally with its own SwiftData store. No iCloud, no backend.

## Three ways to add a card

1. **Scan with camera** — AVFoundation `AVCaptureMetadataOutput`. Recognizes
   QR, Code 128, EAN-13/8, Code 39/93, PDF417, Aztec, UPC-E, ITF14, DataMatrix.
2. **Type/paste a code value** — choose type (QR / Code 128 / PDF417 / Aztec).
3. **Upload an image from Photos** — universal fallback for unsupported
   barcode types or pretty card designs.

All three coexist on a single card.

## Tesla watch key (quick reference)

- **BLE key, no account:** the watch generates a P-256 key (Keychain,
  device-only), you pair it in the car — Start Pairing on the watch → tap your
  physical Tesla key card on the console reader → Confirm on the car screen →
  Verify. No Tesla app, no Add Key menu. Works offline forever after.
- **Setup from the iPhone:** wallet → Tesla Key icon → enter VIN (synced to watch),
  optionally connect your Tesla account.
- **Cloud control (optional):** needs a developer.tesla.com Client ID in
  `TeslaFleetConfig` and, for lock/unlock/climate on 2021+ cars, a running
  `tesla-http-proxy` set as `commandBaseURL` (Tesla requires signed commands).
- **Auto-entry is foreground-only by design:** watchOS stops nil-service BLE
  scans in the background, so auto unlock/lock acts only while the app is
  awake; background "signal loss" is throttling, not distance.
- Vehicle BLE flows can only be validated on the real car — simulators can't.

## Versioning & release workflow

Versions live in `project.yml` only (`MARKETING_VERSION`,
`CURRENT_PROJECT_VERSION`) — Xcode-side edits are overwritten by
`xcodegen generate`. **Bump `CURRENT_PROJECT_VERSION` after every change set**
(App Store Connect rejects duplicate build numbers), bump `MARKETING_VERSION`
for feature releases, regenerate, and update CLAUDE.md / README / OVERVIEW to
match. Archive fresh in the Organizer for each upload — don't re-ship a stale
archive.

## Bundle IDs (change before submitting)

`project.yml` currently uses placeholder bundle IDs:
- iOS: `com.brunopais.eeaccess`
- Watch: `com.brunopais.eeaccess.watchkitapp`
- Watch's `Info.plist` references the iOS bundle ID via
  `WKCompanionAppBundleIdentifier`.

If you change the iOS bundle ID, change all three (and re-run `xcodegen generate`).

## Code signing

The XcodeGen spec leaves `DEVELOPMENT_TEAM` empty. To run on a real device
or upload to the App Store, set your team ID under **Signing & Capabilities**
in Xcode (it persists in the generated project for the active user; commit
your `project.yml` change instead by adding `DEVELOPMENT_TEAM: ABCDE12345`
in the `settings.base` block).

## App Store submission checklist

- [x] App icon set (iOS + watchOS) — custom icon in both `AppIcon.appiconset`s
      (source: `BrandAssets/app-icon-1024.png`). TODO before App Store: clean
      watermark-free regen, iOS 26 dark/tinted variants, watch circular-safe crop
- [ ] Set `DEVELOPMENT_TEAM` and final bundle IDs in `project.yml`
- [ ] Privacy nutrition labels: "Data Not Collected" (everything local)
- [ ] Camera + Photos usage strings (already in `iOS/Info.plist`)
- [ ] Screenshots: iPhone (6.7" + 6.1") and Apple Watch (Series 9 / Ultra)
- [ ] App Store description: emphasize "works on watch without phone"
- [ ] Test on real paired hardware before submission — WatchConnectivity
      behaves differently on simulator

## Known v2 candidates

- iCloud sync across the user's own iPhones/iPads
- Folders / favorites
- Edit existing cards (re-renders barcode automatically)
- Complications (recently-used card on the watch face)
- Apple Wallet (`.pkpass`) export
- Bidirectional sync (delete from watch)
