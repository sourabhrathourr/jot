#!/usr/bin/env bash
# Builds a distributable Jot: an Apple Silicon Jot.app signed with Developer ID and the hardened
# runtime, inside a signed drag-to-install DMG, then (with credentials) notarized and stapled,
# with an EdDSA-signed Sparkle appcast. Adapted from Hun's scripts/package-macos-release.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${JOT_RELEASE_BUILD_DIR:-$ROOT/build/release}"
DIST_DIR="$BUILD_ROOT/dist"
APP="$ROOT/build/Jot.app"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
DMG_SETTINGS="$ROOT/assets/dmg/dmgbuild-settings.py"
DMG_BACKGROUND_1X="$ROOT/assets/dmg/background.png"
DMG_BACKGROUND_2X="$ROOT/assets/dmg/background@2x.png"
DMG_BACKGROUND="$BUILD_ROOT/dmg-background.tiff"
VERSION="${JOT_VERSION:-}"
BUILD_NUMBER="${JOT_BUILD:-}"
NOTARY_PROFILE="${JOT_NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${JOT_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${JOT_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${JOT_NOTARY_ISSUER_ID:-}"
SIGNING_IDENTITY="${JOT_DEVELOPER_ID_APPLICATION:-}"
SPARKLE_ACCOUNT="${JOT_SPARKLE_ACCOUNT:-jot}"
DMGBUILD_BIN="${JOT_DMGBUILD_BIN:-$(command -v dmgbuild || true)}"
GENERATE_APPCAST=0

usage() {
  cat <<'EOF'
Usage:
  scripts/package-release.sh --version X.Y.Z --build NUMBER
    [--notary-profile PROFILE] [--generate-appcast]

Environment:
  JOT_DEVELOPER_ID_APPLICATION  Developer ID Application identity name.
                                Auto-detected when exactly one is installed.
  JOT_NOTARY_PROFILE            Keychain profile created by `notarytool store-credentials`.
  JOT_NOTARY_KEY_PATH           App Store Connect API private key (.p8) path.
  JOT_NOTARY_KEY_ID             App Store Connect API key ID.
  JOT_NOTARY_ISSUER_ID          App Store Connect API issuer ID.
  JOT_DMGBUILD_BIN              dmgbuild 1.6.7 executable (default: on PATH).
  JOT_SPARKLE_ACCOUNT           Keychain account of the Sparkle key (default: jot).
  JOT_SPARKLE_ED_PRIVATE_KEY    CI only: the exported Sparkle private key.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD_NUMBER="${2:-}"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="${2:-}"; shift 2 ;;
    --generate-appcast) GENERATE_APPCAST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION (pass --version X.Y.Z)" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid build number: $BUILD_NUMBER (pass --build N, growing with every release)" >&2
  exit 1
fi
if [ -n "$NOTARY_KEY_PATH$NOTARY_KEY_ID$NOTARY_ISSUER_ID" ] &&
   { [ -z "$NOTARY_KEY_PATH" ] || [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER_ID" ]; }; then
  echo "JOT_NOTARY_KEY_PATH, JOT_NOTARY_KEY_ID and JOT_NOTARY_ISSUER_ID go together." >&2
  exit 1
fi
if [ "$GENERATE_APPCAST" -eq 1 ] && [ -z "$NOTARY_PROFILE$NOTARY_KEY_PATH" ]; then
  echo "An appcast needs a notarized, stapled DMG: pass notary credentials too." >&2
  exit 1
fi
if [ -z "$DMGBUILD_BIN" ] || [ ! -x "$DMGBUILD_BIN" ]; then
  echo "dmgbuild was not found. Install dmgbuild 1.6.7 or set JOT_DMGBUILD_BIN." >&2
  exit 1
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITIES="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')"
  if [ "$(printf '%s\n' "$SIGNING_IDENTITIES" | awk 'NF { n++ } END { print n + 0 }')" -ne 1 ]; then
    echo "Expected exactly one Developer ID Application identity; set JOT_DEVELOPER_ID_APPLICATION." >&2
    security find-identity -v -p codesigning >&2
    exit 1
  fi
  SIGNING_IDENTITY="$SIGNING_IDENTITIES"
fi
echo "Using signing identity: $SIGNING_IDENTITY"

DMG="$DIST_DIR/Jot-$VERSION.dmg"
STABLE_DMG="$DIST_DIR/Jot.dmg"
APPCAST="$DIST_DIR/appcast.xml"
APPCAST_ROOT="$BUILD_ROOT/appcast"
rm -rf "$DIST_DIR" "$APPCAST_ROOT"
mkdir -p "$DIST_DIR"

echo "Building Jot $VERSION ($BUILD_NUMBER)..."
JOT_VERSION="$VERSION" JOT_BUILD="$BUILD_NUMBER" "$ROOT/scripts/bundle.sh" release

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ] || [ "$BUILT_NUMBER" != "$BUILD_NUMBER" ]; then
  echo "Built app is $BUILT_VERSION ($BUILT_NUMBER), expected $VERSION ($BUILD_NUMBER)." >&2
  exit 1
fi
# A release looks exactly like the Jot you test: never ship it without Raycast's icons.
if [ ! -f "$APP/Contents/Resources/Icons/command-symbol.svg" ]; then
  echo "Raycast's icons are missing from the build (scripts/extract-raycast-icons.py)." >&2
  exit 1
fi
APP_ARCHS="$(lipo -archs "$APP/Contents/MacOS/Jot")"
if [ "$APP_ARCHS" != "arm64" ]; then
  echo "Release contains unexpected architectures: $APP_ARCHS" >&2
  exit 1
fi

sign() { codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$@"; }

echo "Signing Sparkle inside-out..."
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/Current"
sign "$SPARKLE_VERSION/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
sign "$SPARKLE_VERSION/Autoupdate"
sign "$SPARKLE_VERSION/Updater.app"
sign "$SPARKLE_FRAMEWORK"

echo "Signing Jot.app..."
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Creating the DMG..."
tiffutil -cathidpicheck "$DMG_BACKGROUND_1X" "$DMG_BACKGROUND_2X" -out "$DMG_BACKGROUND"
"$DMGBUILD_BIN" -s "$DMG_SETTINGS" -D "app=$APP" -D "background=$DMG_BACKGROUND" "Jot" "$DMG"
codesign --force --timestamp --identifier "com.sourabh.jot.dmg" --sign "$SIGNING_IDENTITY" "$DMG"
hdiutil verify "$DMG"
codesign --verify --verbose=2 "$DMG"

if [ -n "$NOTARY_PROFILE$NOTARY_KEY_PATH" ]; then
  echo "Notarizing..."
  if [ -n "$NOTARY_KEY_PATH" ]; then
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  else
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  echo "Signed but not notarized: pass --notary-profile or the JOT_NOTARY_KEY_* values."
fi

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$(basename "$DMG")" > "$DMG.sha256"
ditto "$DMG" "$STABLE_DMG"

if [ "$GENERATE_APPCAST" -eq 1 ]; then
  echo "Generating the Sparkle appcast..."
  mkdir -p "$APPCAST_ROOT"
  ditto "$DMG" "$APPCAST_ROOT/$(basename "$DMG")"
  APPCAST_ARGUMENTS=(
    --download-url-prefix "https://github.com/sourabhrathourr/jot/releases/download/v$VERSION/"
    --link "https://github.com/sourabhrathourr/jot/releases/tag/v$VERSION"
    --maximum-deltas 0
    -o "$APPCAST"
    "$APPCAST_ROOT"
  )
  if [ -n "${JOT_SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$JOT_SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${APPCAST_ARGUMENTS[@]}"
  else
    "$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" "${APPCAST_ARGUMENTS[@]}"
  fi
  grep -q "sparkle:edSignature=" "$APPCAST" || { echo "The appcast has no EdDSA signature." >&2; exit 1; }
fi

cat <<EOF

Release artifacts in $DIST_DIR:
  $(basename "$DMG")   ($APP_ARCHS, $BUILT_VERSION build $BUILT_NUMBER)
  $(basename "$STABLE_DMG")         (the same DMG under a stable name)
  $(basename "$DMG").sha256
EOF
[ "$GENERATE_APPCAST" -eq 1 ] && echo "  appcast.xml"
exit 0
