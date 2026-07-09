# EEAccess — App Store copy (Tesla key release)

Paste-ready metadata for App Store Connect. Character limits noted. Copy is
written to match what a downloaded user can actually do: the **Bluetooth watch
key** + the **card wallet**. It deliberately does NOT promise cloud/remote
control (that's developer-gated and would fail App Review).

---

## Title (max 30)
**EEAccess: Tesla Watch Key**  (25)

Safer alternatives if Apple flags "Tesla" in the name (see Review notes):
- `EEAccess — Watch Car Key` (24)
- `EEAccess: Cards & Car Key` (25)

## Subtitle (max 30)
**Unlock your Tesla, no phone**  (27)

Alternates:
- `Your car key on your wrist` (26)
- `Apple Watch key + card wallet` (29)

## Promotional text (max 170 — editable anytime, no review)
**Primary (168) — leads with the "no subscription" differentiator:**
Finally — a Tesla key for your Apple Watch with no subscription. Lock, unlock and drive with no phone, internet or account. Pay once. Plus all your cards on your wrist.

**Alternate (161) — leads with offline:**
Turn your Apple Watch into a Tesla key — no phone, no internet, no account. Pay once, never a subscription. Your gym and loyalty cards ride along, ready to scan.

## Keywords (max 100, comma-separated, no spaces) — 100/100
remote,fob,keyfob,car,ble,bluetooth,wallet,loyalty,gym,barcode,cybertruck,modely,model3,ev,scan,pass

ASO logic: use **single words** — Apple auto-combines them into phrases ("car
key", "key fob", "tesla remote"), so multi-word phrases just waste characters.
No spaces. Words already in the title/subtitle (tesla, watch, key, unlock,
phone) are indexed automatically, so they're dropped here to make room.
"remote" deliberately targets the popular "Remote for Tesla" competitor searches.

---

## Description (max 4000)

Your Apple Watch is now your Tesla key — and your wallet.

EEAccess turns your Apple Watch into a Bluetooth key for your Tesla. Walk up,
unlock, and drive — no phone, no internet, and no Tesla account. It also keeps
every gym, loyalty, and membership card on your wrist, ready to scan.

YOUR TESLA, ON YOUR WRIST
• Lock and unlock straight from your Apple Watch
• Get in and drive — your watch authorizes drive-away, just like a phone key
• Works fully offline over Bluetooth — no phone nearby, no signal needed
• A watch-face complication puts unlock one tap away
• Best-effort auto-unlock as you walk up (while the Tesla Key screen is open)

ALL YOUR CARDS, NO PLASTIC
• Add gym passes, loyalty and membership cards by scanning their QR or barcode
• See them on your iPhone and on your Apple Watch — standalone, no phone needed
• Scan into the gym after a run without carrying a thing

PRIVATE BY DESIGN
• Your card data and your car key stay on your own devices
• No account needed for the watch key, no tracking, no servers
• The key is generated on your watch and kept in its secure keychain; it never
  leaves the device and isn't synced to the cloud

SET UP IN MINUTES
Enter your VIN on your iPhone, then pair the watch in your car once using your
Tesla key card. After that, your wrist is your key — phone optional.

COMPATIBILITY
Works with Tesla vehicles that support phone keys: Model 3, Model Y, Cybertruck,
and 2021 or newer Model S and Model X. Requires an Apple Watch (Series 6 or
later) on watchOS 26 and an iPhone on iOS 26.

—
EEAccess is an independent app and is not affiliated with, endorsed by, or
sponsored by Tesla, Inc. "Tesla", "Cybertruck", "Model 3", "Model Y", "Model S",
and "Model X" are trademarks of Tesla, Inc., used here only to describe
compatibility.

---

## What's New (release notes, max 4000)

### 2.5
Your Apple Watch Tesla key just got a major update.

• Multiple cars — pair and switch between more than one Tesla.
• Start Drive — enable keyless driving from your wrist or iPhone; press the
  brake and go.
• More reliable walk-up auto-unlock as you approach the car.
• Import your cars from your Tesla account — pick them, don't type the VIN.
• Redeem access codes right in the app.

Older Teslas + cloud (advanced):
• Control 2012–2020 Model S/X over the internet — lock, unlock, drive, climate —
  using your own Tesla account.
• Send commands from Apple Watch over LTE, no iPhone needed.
• Schedule Unlock + Drive to run in 60 seconds — handy for garages with no
  signal.
Cloud features use your own Tesla developer credentials; the Bluetooth watch key
needs none of it.

One-time payment. No subscription, ever.

### 2.1
Your Apple Watch is a Tesla key — and getting full access just got easier.

• NEW: Redeem an access code right in the app. Tap "Redeem Code" on the unlock
  screen, enter your code, and you're in — instant full access.
• Lock, unlock, and drive your Tesla straight from your wrist — no phone, no
  internet, no account.
• Every gym and loyalty card on your Apple Watch, ready to scan.
• Refinements and polish throughout.

One-time payment. No subscription, ever.

### 2.0 (Tesla key launch)
NEW: Your Apple Watch is now a Tesla key.

• Lock, unlock, and drive your Tesla right from your wrist — no phone, no
  internet, no account.
• Pair once in your car with your Tesla key card, then add the new "Tesla Key"
  watch-face complication for one-tap access.
• Best-effort auto-unlock as you approach.
• Fresh new app icon, and the loyalty/gym card wallet you already love.

---

## App Review notes (App Store Connect → App Review Information → Notes)

Important context for the reviewer:

1. The Tesla key feature pairs the Apple Watch directly to the user's own
   Tesla over Bluetooth (the standard phone-key protocol). It requires the
   reviewer's physical vehicle + key card, so it cannot be exercised in a test
   lab. A demonstration video is attached / linked here: [ADD VIDEO LINK].
2. The loyalty/gym card wallet (add a card by scanning a QR/barcode, view it on
   iPhone and Apple Watch) is fully testable without any vehicle.
3. The app does not require a Tesla account and collects no personal data.

[Attach a short screen recording of: pairing flow on the watch, and lock/unlock
on a real car. This is the single best way to avoid a "couldn't verify the
feature" rejection.]

---

## Pre-submission checklist (important)

- [ ] **Decide on "Tesla" in the app name.** Using a trademark in the title can
      trigger rejection (guideline 4.5.4 / trademark). "for Tesla" style names
      are common and often approved, but the safer route is to keep "Tesla" only
      in subtitle/keywords/description. Disclaimer above is required either way.
- [ ] **Attach an App Review demo video** of pairing + unlock on a real car —
      reviewers can't test the key without a vehicle.
- [ ] **Cloud / "Connect Tesla Account" UI:** in the shipping build this shows
      "Not configured" (no developer Client ID). A reviewer may flag a
      non-functional button. Recommend hiding the cloud section until it's
      configured, OR leave it (it honestly states it's unavailable). Do NOT
      advertise remote/cloud control in metadata until it actually works for
      end users.
- [ ] **Privacy nutrition label:** "Data Not Collected" — card data and the car
      key stay on-device; the only network call is the iTunes logo search.
- [ ] **Screenshots:** lead with the watch unlocking the car (see the screenshot
      concept). Required sizes: 6.7" + 6.1" iPhone, and Apple Watch.
- [ ] **Support URL + marketing URL** filled in.
