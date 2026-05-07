#!/usr/bin/env bash
# Compile Resources/AppIcon-source.png into:
#   - Resources/AppIcon.icns  (bundled into MacPulse.app)
#   - docs/icon.png           (256px copy used by README.md)
# Run from the repo root:  scripts/make-icon.sh
set -euo pipefail

SOURCE="Resources/AppIcon-source.png"
ICONSET="Resources/AppIcon.iconset"
ICNS="Resources/AppIcon.icns"
DOCS_ICON="docs/icon.png"

if [ ! -f "$SOURCE" ]; then
    echo "error: $SOURCE not found" >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET" docs

# macOS .iconset standard sizes. Each size is the source rescaled with sips.
declare -a SIZES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for entry in "${SIZES[@]}"; do
    name="${entry%%:*}"
    size="${entry##*:}"
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"
echo "✓ icns    $ICNS"

sips -z 256 256 "$SOURCE" --out "$DOCS_ICON" >/dev/null
echo "✓ readme  $DOCS_ICON"
