# EEAccess — Product Overview

> A simple wallet for loyalty cards, gym passes, and any scannable membership
> card — with a standalone Apple Watch app so you can leave your phone behind.
> Plus: your Apple Watch as a **Tesla Bluetooth key** — lock, unlock, and
> drive with no phone, no internet, and no Tesla account.

## Purpose

People carry too many plastic cards: gyms, supermarkets, libraries, clubs,
loyalty programs. Most have a barcode or QR code that just needs to be
scanned at a counter or turnstile. EEAccess turns that pile of plastic
into a single screen you always have on you — and importantly, it puts
those codes on the **Apple Watch as a standalone app**, so you can scan
into the gym after a run without bringing a phone.

## Goals

- **Replace physical cards** with a digital wallet you actually use.
- **Work on the wrist**, not just the phone — the watch app is fully
  independent once cards have been synced.
- **Stay simple** — no accounts, no backend, no subscription.
- **Privacy-first** — card data lives on the user's own devices.
- **Ship fast** — first version targets the App Store with the smallest
  feature set that's genuinely useful.

## Who it's for

- People who run, walk, or commute without a phone but still need their
  gym/club/transit/library card to get in.
- Anyone whose wallet is full of plastic loyalty cards they rarely have
  on them when needed.
- Apple Watch users who treat the watch as a primary device.

## Functionalities

### Adding a card

A new card has three parts the user can fill independently — any one of
them on its own is enough to save:

- **Scan with the camera.** Supports QR, Code 128, EAN-13/8, Code 39/93,
  PDF417, Aztec, UPC-E, ITF14, DataMatrix.
- **Paste/type a code value.** Choose the type (QR / Code 128 / PDF417 /
  Aztec) and the app renders the barcode itself.
- **Paste a barcode image** from clipboard. The Vision framework decodes
  it into value + symbology in the background. If the symbology is
  renderable (QR / Code 128 / PDF417 / Aztec) the app re-renders fresh
  at save time; otherwise (EAN-13, Data Matrix, etc.) the pasted image
  itself is stored and shown as the barcode.
- **Upload a photo of the card.** For any barcode type the camera
  doesn't support, or just to show the card design.
- **Paste a card image** from clipboard. Same flow as upload, just
  sourced from the pasteboard.

Plus two visual identifiers:

- **Logo image.** Shown in the list and on the watch instead of a
  generic colored tag. Three ways to set one, all routed through a
  circular crop sheet for precise positioning:
  - **App Store search** — type a brand/app name (defaults to the card
    name); results come from Apple's free public iTunes Search API and
    show the actual iOS App Store icons, biased to the user's region so
    local brands rank. Tap a result and it opens in the crop sheet.
  - **Upload from Photos** — `PhotosPicker`.
  - **Paste from clipboard** — `PasteButton` accepts any image on the
    pasteboard (no privacy-banner spam thanks to the system control).
- **Color tag fallback.** Eight preset colors when no logo is set.

### Browsing & using cards

- **iPhone list** — logo, name, and a one-line preview of the barcode
  value. Empty state guides the user to add their first card.
- **iPhone detail** — the rendered barcode displayed full-width on a
  white background, max brightness, screen kept awake until you leave
  the page (so the scanner reads cleanly without dimming).
- **Apple Watch list** — compact, with mini circular logos for quick
  recognition.
- **Apple Watch detail** — the barcode shown on a white card with
  rounded corners; uses the same pre-rendered PNG from the phone, so
  no rendering happens on the watch.

### Sync

- iPhone → Watch one-way sync via `WCSession.transferUserInfo`.
- Each add or delete is one queued payload — survives app restarts and
  delivers when the watch is reachable.
- Cards on the watch live in their own SwiftData store and remain
  available even if the iPhone app is uninstalled.

### Tesla watch key

- **Pair once, in the car** (watch sends the key over Bluetooth; you authorize
  by tapping your physical Tesla key card on the console and confirming on the
  car's screen). VIN is entered on the iPhone and synced to the watch.
- **Daily use from the wrist:** Unlock / Lock buttons, "Connect to drive"
  (presence authorizes drive-away like a phone key), and a watch-face
  complication that jumps straight to the key screen.
- **Auto-entry (best-effort):** unlocks on approach / locks on walk-away while
  the app is awake on screen; deliberately conservative — auto-unlock requires
  the app frontmost so unlocking is always tied to user intent.
- **Cloud control from the iPhone (optional):** Tesla account sign-in, battery
  / lock / temperature snapshot, wake, and — with Tesla's signing proxy
  configured — remote lock/unlock and climate.
- **Privacy unchanged:** the key is generated and stored on the watch
  (device-only Keychain, never synced); BLE control needs no account and works
  fully offline. Supported: Model 3/Y/Cybertruck, and 2021+ Model S/X.

## What's implemented

- [x] iOS app: list, detail, add, **edit** (scan / type / upload / paste / logo)
- [x] Edit existing cards from the detail screen — pre-fills all fields,
      mutates the existing record, re-syncs to the watch on save
- [x] Paste-from-clipboard for logo, barcode image, and card image
- [x] Vision-based barcode decoding for pasted barcode images (auto-fills
      value + type when possible; falls back to image-only otherwise)
- [x] Logo via clipboard paste or upload from Photos, plus an interactive
      pan/zoom crop sheet that fits any image into the circular logo space
- [x] watchOS standalone app: list, detail (no phone required after sync)
- [x] SwiftData persistence on both platforms
- [x] WatchConnectivity sync (upsert + delete)
- [x] Barcode rendering done on iOS, shipped as PNG to watch
      (CoreImage barcode generators don't exist on watchOS)
- [x] Image resize + JPEG compression for uploads
- [x] Camera permission + Photos permission strings in Info.plist
- [x] Embedded companion watch target (the watch `.app` is embedded
      inside the iOS app's `Watch/` folder at build time, so installing
      the iOS app from the App Store auto-installs the watch app on the
      paired Apple Watch — no separate watch-side install)
- [x] Tesla BLE watch key: in-car pairing wizard, lock/unlock,
      connect-to-drive, forget/re-verify key (vendored `TeslaKeyKit`
      protocol package, 184 tests)
- [x] Tesla presence auto-entry (app-active gated) + "Tesla Key"
      watch-face complication with deep link
- [x] iPhone Tesla setup: VIN entry synced to watch, account OAuth
      (PKCE), cloud state/wake/lock/unlock/climate via Fleet API
      (commands require the user's tesla-http-proxy on 2021+ cars)
- [x] Paywall: 14-day trial + one-time unlock, Redeem Code, TestFlight
      and App Review builds bypass via sandbox-receipt check
- [x] XcodeGen-driven project generation — single source of truth in
      `project.yml`, no target-membership accidents
- [x] Both targets build clean for simulator

## What's not yet implemented

- [ ] Delete cards from the watch (today: phone only, watch is read-only)
- [ ] iCloud sync between the user's own iPhones/iPads
- [ ] Search or filter in the card list
- [ ] Folders / tags / favorites
- [ ] Watch complications (most-recent card on the watch face)
- [ ] Apple Wallet (`.pkpass`) export for cards that support it
- [x] App icon (custom "access cards + Cybertruck" mark, iOS + watch);
      launch screen still default
- [ ] App icon iOS 26 dark/tinted variants + watch circular-safe recompose
      (current icon's corner detail is cropped by the watch circular mask)
- [ ] App Store assets (screenshots, description, privacy labels)
- [ ] Final code signing (`DEVELOPMENT_TEAM` is empty in `project.yml`)

## Technical stack

| Layer | Technology |
| --- | --- |
| UI | SwiftUI (iOS 17+, watchOS 10+) |
| Persistence | SwiftData — local stores, no shared container |
| Phone ↔ Watch sync | WatchConnectivity (`transferUserInfo`) |
| Barcode generation | Core Image `CIFilter` (iOS only) |
| Camera scanning | AVFoundation `AVCaptureMetadataOutput` |
| Image picker | PhotosUI `PhotosPicker` |
| Clipboard paste | `PasteButton` + `NSItemProvider` (system-rendered, privacy-safe) |
| Logo crop | Custom SwiftUI sheet with pan/zoom gestures, render on background task |
| App icon search | iTunes Search API (`itunes.apple.com/search?media=software`), no key, no quota |
| Barcode decoding | `VNDetectBarcodesRequest` (Vision framework) |
| Project file | XcodeGen (`project.yml` is the source of truth) |

## Privacy

- **Card data never leaves the user's devices.** No backend, no analytics,
  no accounts.
- **One outbound endpoint:** `itunes.apple.com/search` (Apple's public
  iTunes Search API), called only while the user is typing in the logo
  search field of the Add Card sheet. The query string and a region
  hint go up; app metadata + icon URLs come back. Tapping a result
  downloads the icon image from `is*-ssl.mzstatic.com` (Apple's CDN).
  No identifiers, no analytics, no third parties involved.
- **App Store privacy labels** can be set to "Data Not Collected" — the
  iTunes API doesn't collect anything from the user; it's a one-shot
  GET the user controls by typing.

## Deployment readiness

| Item | Status |
| --- | --- |
| iOS target builds | Ready |
| watchOS target builds | Ready |
| App icons | Set (custom icon, iOS + watch) |
| Launch screen | Default (auto-generated) |
| Bundle IDs | Placeholder (`com.brunopais.eeaccess`) |
| Code signing | Not configured |
| TestFlight | Not submitted |
| App Store | Not submitted |

## Suggested next steps

1. **App icon** — design once, drop into both Asset catalogs.
2. **Edit-card flow** — lets users fix mistakes; cheap to add.
3. **Real bundle IDs + Team ID** — set in `project.yml`, regenerate.
4. **Screenshots + App Store listing** — emphasize the "works on watch
   without phone" angle, since that's the differentiator.
5. **TestFlight** — get feedback from real wrists before App Store.
6. **iCloud sync (v2)** — `ModelConfiguration(cloudKitDatabase: .private)`
   once the basics are in users' hands.
