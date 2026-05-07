#!/usr/bin/env bash
# Bundle MacPulse.app from the swift build output.
# Usage: scripts/build-app.sh [version]
#   version defaults to "dev"; the GitHub release workflow passes vX.Y.Z.
set -euo pipefail

VERSION="${1:-dev}"
APP="MacPulse.app"

# Default to a single-arch debug build for fast iteration. Pass MACPULSE_RELEASE=1
# to mirror what the release workflow does (universal release binary).
if [ "${MACPULSE_RELEASE:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build
    BIN_PATH="$(swift build --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/MacPulse" "$APP/Contents/MacOS/MacPulse"
chmod +x "$APP/Contents/MacOS/MacPulse"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacPulse</string>
    <key>CFBundleIdentifier</key>
    <string>app.macpulse.MacPulse</string>
    <key>CFBundleName</key>
    <string>MacPulse</string>
    <key>CFBundleDisplayName</key>
    <string>MacPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ built  $APP  (version ${VERSION})"
