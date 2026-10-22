#!/bin/bash
# Builds Jot.app (menu-bar agent) into ./build, ad-hoc signed for local use.
# scripts/package-release.sh re-signs it with Developer ID for distribution.
#
#   JOT_VERSION=0.1.0  CFBundleShortVersionString (default 0.1.0)
#   JOT_BUILD=1        CFBundleVersion, must grow with every release (default 1)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="${JOT_VERSION:-0.1.0}"
BUILD="${JOT_BUILD:-1}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Jot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Jot" "$APP/Contents/MacOS/Jot"
cp -R Sources/JotKit/Resources/Fonts "$APP/Contents/Resources/Fonts"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Raycast's icons, copied from your own Raycast.app (see docs/DEVELOPMENT.md).
python3 -I scripts/extract-raycast-icons.py "$APP/Contents/Resources/Icons"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.sourabh.jot</string>
  <key>CFBundleName</key><string>Jot</string>
  <key>CFBundleDisplayName</key><string>Jot</string>
  <key>CFBundleExecutable</key><string>Jot</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.sourabh.jot</string>
    <key>CFBundleURLSchemes</key><array><string>jot</string></array>
  </dict></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License. Inter and JetBrains Mono are licensed under the SIL Open Font License.</string>
  <key>SUFeedURL</key><string>https://github.com/sourabhrathourr/jot/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>vGGsqXe22qQsoBSXsoFqJ2jLAmuYywIuVRYcxU6rhGw=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP ($VERSION, build $BUILD)"
