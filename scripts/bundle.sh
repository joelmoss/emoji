#!/bin/sh
# Builds Emoji.app (menu-bar app, no Dock icon). Run from repo root.
# SIGN_ID overrides the signing identity; SIGN_ID=- signs ad-hoc (Accessibility then resets on every rebuild).
set -e
swift build -c release --disable-sandbox
BIN=$(swift build -c release --show-bin-path)

APP=Emoji.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Emoji" "$APP/Contents/MacOS/"
cp Sources/Emoji/emojis.json "$APP/Contents/Resources/"
# Release builds look for resource bundles in Contents/Resources (debug builds use the .app root,
# which codesign rejects, so only release-built apps work). KeyboardShortcuts' Recorder needs its bundle.
cp -R "$BIN/KeyboardShortcuts_KeyboardShortcuts.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.joelmoss.emoji</string>
  <key>CFBundleName</key><string>Emoji</string>
  <key>CFBundleExecutable</key><string>Emoji</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

codesign --force --sign "${SIGN_ID:-Apple Development: Joel Moss (K7JL9AWZ26)}" "$APP"
echo "Built $APP, signed. Grant Accessibility once (System Settings > Privacy & Security); it persists across rebuilds."
