# BrandAssets/source

Raw, unprocessed icon sources. Edit / replace `icon-source.{jpg,png}`
when you want to change the app icon.

## Convention

- **`icon-source.png`** or **`icon-source.jpg`** — the master file.
  Any size, any aspect ratio, with or without flat padding, with or
  without alpha. The pipeline cleans it.
- Keep prior versions here too if useful (e.g. `icon-source-v1.png`,
  `icon-source-experimental.png`) — only `icon-source.{png,jpg}` is
  treated as canonical.

## Pipeline (run when source changes)

```bash
SRC=BrandAssets/source/icon-source.jpg   # or .png
CANONICAL=BrandAssets/eeaccess-app-icon-1024.png
IOS_DST=iOS/Assets.xcassets/AppIcon.appiconset/eeaccess-app-icon-1024.png
WATCH_DST=Watch/Assets.xcassets/AppIcon.appiconset/eeaccess-app-icon-1024.png

# detect the icon's flat-color border, trim it, resize to 1024x1024,
# strip alpha (App Store requires opaque RGB)
magick "$SRC" \
  -bordercolor "#0A1B39" -border 1 -fuzz 8% -trim +repage \
  -resize 1024x1024 \
  -background "#0A1B39" -gravity center -extent 1024x1024 \
  -alpha off -strip \
  "$CANONICAL"

cp "$CANONICAL" "$IOS_DST"
cp "$CANONICAL" "$WATCH_DST"
```

The `-bordercolor` value should match the icon's outermost padding
color (here `#0A1B39`, the dark navy of the EB QR design). For a
different design with different padding, swap to that color.
