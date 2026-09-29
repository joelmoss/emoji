#!/bin/sh
# Usage: scripts/bundle.sh dev|release   (run from repo root)
#   dev      debug build   -> "Emoji Dev.app", com.joelmoss.emoji.dev, Apple Development signature
#   release  release build -> "Emoji.app",     com.joelmoss.emoji,     Developer ID signature + hardened runtime
# SIGN_ID overrides the identity; SIGN_ID=- signs ad-hoc (Accessibility then resets on every rebuild).
# Release is signed but not notarized, so Gatekeeper on other Macs will still object.
set -e
case "$1" in
  dev)
    CONFIG=debug NAME="Emoji Dev" ID=com.joelmoss.emoji.dev
    SIGN="${SIGN_ID:-Apple Development: Joel Moss (K7JL9AWZ26)}" FLAGS="" ;;
  release)
    CONFIG=release NAME="Emoji" ID=com.joelmoss.emoji
    SIGN="${SIGN_ID:-Developer ID Application: Joel Moss (B898J443L9)}" FLAGS="--options runtime --timestamp" ;;
  *) echo "usage: $0 dev|release" >&2; exit 1 ;;
esac

swift build -c "$CONFIG" --disable-sandbox
BIN=$(swift build -c "$CONFIG" --show-bin-path)

APP="$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Emoji" "$APP/Contents/MacOS/$NAME"
cp Sources/Emoji/emojis.json "$APP/Contents/Resources/"
# SwiftPM's Bundle.module looks in Contents/Resources first. Not the .app root: codesign rejects that.
# KeyboardShortcuts' Recorder needs its bundle.
cp -R "$BIN/KeyboardShortcuts_KeyboardShortcuts.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

# shellcheck disable=SC2086 # FLAGS is deliberately word-split
codesign --force --sign "$SIGN" $FLAGS "$APP"
echo "Built $APP ($CONFIG), signed. Grant Accessibility once (System Settings > Privacy & Security)."
