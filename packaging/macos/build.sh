#!/bin/bash
# Builds Blink.app. Pass --install to copy it into Applications and relaunch.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP=".build/Blink.app"
BUNDLE_ID="com.manuelpalenzuela.blink"
VERSION="1.0"

echo "▸ core self-test"
swift run -c release blink-selftest

echo "▸ compiling"
swift build -c release --product blink

echo "▸ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/blink "$APP/Contents/MacOS/Blink"

echo "▸ icon"
rm -rf .build/Blink.iconset
swift packaging/macos/makeicon.swift .build/Blink.iconset >/dev/null
iconutil -c icns .build/Blink.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Blink</string>
  <key>CFBundleDisplayName</key><string>Blink</string>
  <key>CFBundleExecutable</key><string>Blink</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "▸ signing (ad-hoc)"
codesign --force --sign - "$APP"

if [[ "${1:-}" != "--install" ]]; then
  echo "▸ built $APP (pass --install to install and launch)"
  exit 0
fi

DEST=/Applications
if ! [[ -w /Applications ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi
echo "▸ installing to $DEST"
pkill -x Blink || true
sleep 0.5
rm -rf "$DEST/Blink.app"
cp -R "$APP" "$DEST/Blink.app"
open "$DEST/Blink.app"
echo "▸ Blink is running — look for the eye in your menu bar"
