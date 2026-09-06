#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
UNIVERSAL=false
case "${1:-}" in
  --universal) UNIVERSAL=true ;;
  "") ;;
  *) echo "Usage: $0 [--universal]" >&2; exit 2 ;;
esac
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/windowpilot-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/WindowPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if $UNIVERSAL; then
  BINARIES=()
  for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx26.0"
    swift build -c release --triple "$TRIPLE"
    BIN_DIR="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"
    BINARIES+=("$BIN_DIR/WindowPilot")
  done
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/WindowPilot"
  lipo "$APP/Contents/MacOS/WindowPilot" -verify_arch arm64 x86_64
else
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  cp "$BIN_DIR/WindowPilot" "$APP/Contents/MacOS/WindowPilot"
fi
SPARKLE_SOURCE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto --norsrc --noextattr "$SPARKLE_SOURCE" "$FRAMEWORK"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/WindowPilotIcon.icns Resources/Sparkle-LICENSE.txt "$APP/Contents/Resources/"
# Sign outside File Provider folders, where FinderInfo can be reattached.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
SIGN_IDENTITY="${WINDOWPILOT_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk '/Developer ID Application:/{print $2; exit}')"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development:/{print $2; exit}')"
  fi
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi
SIGN_OPTIONS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--timestamp); fi
# Sign helpers from the inside out, preserving the downloader's entitlements.
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  # Library validation requires a real Team ID; development artifacts use ad-hoc signing.
  codesign --force --sign - "$APP"
else
  codesign "${SIGN_OPTIONS[@]}" "$APP"
fi
codesign --verify --deep --strict "$APP"
mkdir -p dist
# Replace the generated bundle so removed resources cannot survive a rebuild.
rm -rf dist/WindowPilot.app
ditto --norsrc --noextattr "$APP" dist/WindowPilot.app
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/WindowPilot.zip
printf 'Built: %s\n' "$PROJECT_DIR/dist/WindowPilot.app"
