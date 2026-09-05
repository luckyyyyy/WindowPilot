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
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/WindowPilotIcon.icns "$APP/Contents/Resources/"
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
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
ditto --norsrc --noextattr "$APP" dist/WindowPilot.app
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/WindowPilot.zip
printf 'Built: %s\n' "$PROJECT_DIR/dist/WindowPilot.app"
