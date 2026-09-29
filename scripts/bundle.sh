#!/bin/sh
# Builds Emoji.app (menu-bar app, no Dock icon). Run from repo root.
set -e
swift build -c release --disable-sandbox
BIN=$(swift build -c release --show-bin-path)

APP=Emoji.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Emoji" "$APP/Contents/MacOS/"
cp Sources/Emoji/emojis.json "$APP/Contents/Resources/"
# SwiftPM's Bundle.module accessor looks in the .app root, not Resources.
cp -R "$BIN/KeyboardShortcuts_KeyboardShortcuts.bundle" "$APP/"

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

# No codesign: it rejects the bundle at the .app root. The linker already ad-hoc signed the binary.
echo "Built $APP. Grant it Accessibility (re-grant after each rebuild: identity is the binary hash) in System Settings > Privacy & Security."
