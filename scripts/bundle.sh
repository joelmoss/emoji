#!/bin/sh
# Usage: scripts/bundle.sh dev|release   (run from repo root)
#   dev      debug build   -> "Emoji Dev.app", com.joelmoss.emoji.dev, Apple Development signature
#   release  release build -> "Emoji.app",     com.joelmoss.emoji,     Developer ID signature + hardened runtime
# SIGN_ID overrides the identity; SIGN_ID=- signs ad-hoc (Accessibility then resets on every rebuild).
# VERSION (default 0.1.0) and BUILD (default: commit count, must only ever go up) set the bundle versions.
# NOTARIZE=1 (release only) submits to Apple, staples the ticket and writes Emoji-$VERSION.zip. Auth is the
# keychain profile "emoji" (xcrun notarytool store-credentials emoji ...), or set NOTARY_ARGS, e.g.
# NOTARY_ARGS="--key AuthKey.p8 --key-id ID --issuer ISSUER" in CI.
set -e
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
case "$1" in
  dev)
    CONFIG=debug NAME="Emoji Dev" ID=com.joelmoss.emoji.dev
    SIGN="${SIGN_ID:-Apple Development: Joel Moss (K7JL9AWZ26)}" FLAGS="" ;;
  release)
    CONFIG=release NAME="Emoji" ID=com.joelmoss.emoji
    SIGN="${SIGN_ID:-Developer ID Application: Joel Moss (B898J443L9)}" FLAGS="--options runtime --timestamp" ;;
  *) echo "usage: $0 dev|release" >&2; exit 1 ;;
esac
[ "${NOTARIZE:-}" != 1 ] || [ "$1" = release ] || { echo "NOTARIZE=1 only applies to release" >&2; exit 1; }

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

# shellcheck disable=SC2086 # FLAGS is deliberately word-split
codesign --force --sign "$SIGN" $FLAGS "$APP"

if [ "${NOTARIZE:-}" = 1 ]; then
  WORK=$(mktemp -d)
  ditto -c -k --keepParent "$APP" "$WORK/$NAME.zip"
  # shellcheck disable=SC2086 # NOTARY_ARGS is deliberately word-split
  xcrun notarytool submit "$WORK/$NAME.zip" ${NOTARY_ARGS:---keychain-profile emoji} --wait --timeout 30m
  rm -rf "$WORK"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vv -t exec "$APP"
  # Zip after stapling: a zip made before it ships without the ticket.
  ditto -c -k --keepParent "$APP" "$NAME-$VERSION.zip"
  echo "Notarized and stapled: $NAME-$VERSION.zip"
fi

echo "Built $APP $VERSION ($BUILD, $CONFIG), signed. Grant Accessibility once (System Settings > Privacy & Security)."
