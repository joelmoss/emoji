#!/bin/sh
# Usage: scripts/bundle.sh dev|release   (run from repo root)
#   dev      debug build   -> "Emoji Dev.app", com.joelmoss.emoji.dev, Apple Development signature
#   release  release build -> "Emoji.app",     com.joelmoss.emoji,     Developer ID signature + hardened runtime
# SIGN_ID overrides the identity; SIGN_ID=- signs ad-hoc (Accessibility then resets on every rebuild).
# VERSION (default 0.1.0) and BUILD (default: commit count, must only ever go up) set the bundle versions.
# NOTARIZE=1 (release only) notarizes and staples the app, then builds, signs, notarizes and staples
# Emoji-$VERSION.dmg (the release artifact; Sparkle updates from it too). Auth is the
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

# Sparkle updates are release-only: the dev build must never try to replace itself with the release app.
# The public key is generated once with Sparkle's generate_keys (see README).
SPARKLE_KEYS=""
if [ "$1" = release ]; then
  PUBKEY=$(cat scripts/sparkle_public_key.txt 2>/dev/null || true)
  if [ -n "$PUBKEY" ]; then
    SPARKLE_KEYS="<key>SUFeedURL</key><string>https://github.com/joelmoss/emoji/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$PUBKEY</string>"
  elif [ "${NOTARIZE:-}" = 1 ]; then
    echo "scripts/sparkle_public_key.txt is missing: run generate_keys first (see README)" >&2
    exit 1
  fi
fi

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

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$SPARKLE"
# Not sandboxed, so Sparkle's XPC services are optional; dropping them leaves less to sign and notarize.
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Versions/B/XPCServices"
# SwiftPM only sets @loader_path as the rpath; the framework lives in Contents/Frameworks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/$NAME"

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
  $SPARKLE_KEYS
</dict></plist>
EOF

# Inside out: notarization rejects nested code that isn't signed with the same identity and runtime.
for item in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
  # shellcheck disable=SC2086 # FLAGS is deliberately word-split
  codesign --force --sign "$SIGN" $FLAGS "$item"
done

if [ "${NOTARIZE:-}" = 1 ]; then
  # shellcheck disable=SC2086 # NOTARY_ARGS is deliberately word-split
  notarize() { xcrun notarytool submit "$1" ${NOTARY_ARGS:---keychain-profile emoji} --wait --timeout 30m; }
  WORK=$(mktemp -d)

  # 1. App first, so the copy inside the DMG carries its own stapled ticket and launches offline.
  ditto -c -k --keepParent "$APP" "$WORK/$NAME.zip"
  notarize "$WORK/$NAME.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vv -t exec "$APP"

  # 2. DMG: the app plus an Applications shortcut to drag it onto.
  DMG="$NAME-$VERSION.dmg"
  rm -f "$DMG"
  mkdir "$WORK/dmg"
  ditto "$APP" "$WORK/dmg/$APP"
  ln -s /Applications "$WORK/dmg/Applications"
  hdiutil create -volname "$NAME" -srcfolder "$WORK/dmg" -format UDZO -ov "$DMG" >/dev/null
  codesign --force --sign "$SIGN" --timestamp "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vv -t open --context context:primary-signature "$DMG"
  rm -rf "$WORK"
  echo "Notarized and stapled: $DMG"
fi

echo "Built $APP $VERSION ($BUILD, $CONFIG), signed. Grant Accessibility once (System Settings > Privacy & Security)."
