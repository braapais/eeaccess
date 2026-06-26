# EEAccess — App Icon & Logo Brief

A brief for a professional designer / studio. Everything they need to deliver a
final, ship-ready app icon (and optional wordmark) is below.

## 1. The product

**EEAccess** is an iOS + standalone Apple Watch app with two jobs unified by one
idea — **access**:

1. **A wallet for scannable cards** — gym passes, loyalty cards, memberships,
   transit. Their QR codes and barcodes live on the Apple Watch, so you can scan
   into the gym or shop **without your phone**.
2. **A Tesla key on your wrist (the hero feature)** — the watch pairs directly to
   the car over Bluetooth and **locks, unlocks, and drives with no phone, no
   internet, and no account**.

Positioning line: *"One credential for everything you walk up to — the gym, the
shop, and your car."*

## 2. What we need

- **Primary:** the **app icon** (iOS + watchOS).
- **Secondary (nice to have):** a horizontal **wordmark / logo lockup** ("EEAccess")
  for the App Store page, website, and marketing.

## 3. Concept direction (where we've landed)

A single, flat **"access" mark** that fuses:

- **A small stack of scannable cards** (a card peeking behind the front one) →
  reads as a *wallet of gym/loyalty cards*.
- On the front card: a **QR code** and a **membership barcode** (the universal
  "scan to enter" cue) plus the **EE** lettering.
- **An angular, modern Cybertruck-style car silhouette** → the Tesla key half.

So: **card stack = all your cards, car silhouette = your car key**, joined by the
idea of access. We have rough SVG concept sketches (stack / gantry / card-first /
gate-first directions) that can be shared as reference — the **"stack"** direction
is the current favorite. Treat these as *thought-starters, not constraints* — we
want the studio's craft on proportion, balance, and finish.

## 4. Must include

- A **card / QR** element (loyalty + gym wallet).
- The **EE** lettering or monogram (EEAccess; "EE" = Elba Everywhere).
- A **modern, angular car** that clearly evokes a Cybertruck **silhouette**
  (low, sharp, single straight raked roofline, angular wheel arches) — **without**
  copying Tesla's trademarks.
- A sense of **access / entry** (the card unlocking things).

## 5. Must avoid (important — App Store + legal)

- **No Tesla logo, "T" mark, wordmark, or Tesla red.** Nominative text like
  "works with Tesla" is fine in copy, but the icon must not use Tesla's brand
  assets or imply official endorsement. The car is a **generic angular
  silhouette**, not a Tesla badge.
- **No literal key glyph** as the main element (we moved away from that — the
  *card* is the credential).
- **No busy "scene"** that turns to mush at small sizes — see legibility below.
- No photorealism, no heavy gradients/bevels/drop-shadows that don't scale.

## 6. Brand personality

Modern, trustworthy, effortless, quietly premium, privacy-first. Confident and
minimal — closer to a fintech/Apple-Wallet aesthetic than a gadget app. Flat and
geometric, not skeuomorphic.

## 7. Color palette

| Role | Hex | Notes |
|---|---|---|
| Primary background (navy) | `#0B1C3D` → `#15325E` | Vertical gradient; solid fallback `#0C1F44` |
| Accent (green) | `#29C78C` | Brand green (brightest highlight `#2FD79A`, deeper `#1FB985`) |
| Card / light | `#FFFFFF` | Cards |
| Car / steel | `#DDE7F4` | Cool light-steel for the vehicle |
| Ink | `#0B1C3D` / `#14181E` | QR modules, wheels, fine detail |

Navy + green is the established in-app palette (paywall, accent color, the
in-app Tesla-key glyph) — please keep the icon consistent with it.

## 8. Typography

- "EE" / "EEAccess" should feel **geometric, bold, modern sans** (think Inter,
  SF, Söhne, or a custom geometric). Tight letter-spacing on the "EE".
- The studio may propose a custom "EE" monogram — welcome.

## 9. Legibility (hard requirement)

The icon **must remain clear and recognizable at 40×40 px and smaller** — it
appears in Settings (29 pt), Spotlight (40 pt), notifications, and as an Apple
**Watch complication** (very small, sometimes circular). Test every concept at
those sizes. One dominant idea; supporting cues must not become noise. If a
detail (barcode, wheels) disappears at 40 px, simplify it.

## 10. Deliverables & technical specs (what the build needs)

**Source**
- Editable **vector** master: Figma (preferred) or `.ai`/`.svg`, fully layered.

**App icon — iOS (Xcode "single size" asset)**
- **1024 × 1024 px PNG**, sRGB, **flattened, no transparency / no alpha**, **no
  rounded corners** (the system applies the mask), full-bleed artwork.
- **iOS 18/26 icon variants — provide all three:**
  - **Light** (the main icon).
  - **Dark** (artwork on a dark/transparent-aware treatment per Apple's
    Human Interface Guidelines for dark app icons).
  - **Tinted** (a **grayscale/monochrome** version that reads when the system
    applies a single tint — design must hold up with no color).

**App icon — watchOS**
- **1024 × 1024 px PNG**, same rules. The watch masks to a **circle**, so keep
  all key elements within a centered circular safe area; provide a
  watch-tuned composition if the square version crops badly.

**Safe area**
- Keep critical elements within the **center ~80%**; nothing important in the
  outer ~10% (corner masking + small-size cropping).

**Optional / secondary**
- Horizontal **wordmark lockup** (icon + "EEAccess") in light and dark, vector +
  PNG.
- **Monochrome / single-color** logo version.
- App Store **feature graphic** / screenshot template using the same system.

**File handoff**
- Deliver: layered source, plus exported PNGs named clearly
  (`AppIcon-1024.png`, `AppIcon-Dark-1024.png`, `AppIcon-Tinted-1024.png`,
  `AppIcon-Watch-1024.png`). We drop these straight into Xcode asset catalogs.

## 11. Practical notes for the studio

- The app is built for **iOS 26 / watchOS 26** (latest). Use Apple's current
  app-icon guidance (single 1024 master + light/dark/tinted variants).
- We have working SVG concept sketches and the in-app green/navy palette we can
  share on request — happy to give the designer the reference files.
