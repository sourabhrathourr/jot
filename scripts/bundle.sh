#!/bin/bash
# Builds Jot.app (menu-bar agent, ad-hoc signed) into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Jot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Jot" "$APP/Contents/MacOS/Jot"
cp -R Sources/JotKit/Resources/Fonts "$APP/Contents/Resources/Fonts"
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
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.sourabh.jot</string>
    <key>CFBundleURLSchemes</key><array><string>jot</string></array>
  </dict></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Inter and JetBrains Mono are licensed under the SIL Open Font License.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
