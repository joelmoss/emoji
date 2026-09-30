#!/bin/sh
# Regenerates assets/icon/AppIcon.icns (and the README's AppIcon.png) from AppIcon.svg. Needs librsvg (brew install librsvg);
# iconutil ships with macOS. Commit the .icns: bundle.sh just copies it, so CI needs neither tool.
set -e
cd "$(dirname "$0")/../assets/icon"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  rsvg-convert -w "${spec%%:*}" -h "${spec%%:*}" AppIcon.svg -o "$SET/icon_${spec#*:}.png"
done
iconutil -c icns "$SET" -o AppIcon.icns
rsvg-convert -w 256 -h 256 AppIcon.svg -o AppIcon.png  # shown in README.md
rm -rf "$(dirname "$SET")"
echo "Wrote assets/icon/AppIcon.icns and AppIcon.png"
