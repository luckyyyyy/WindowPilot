#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
PROFILE="${WINDOWPILOT_NOTARY_PROFILE:-WindowPilot-notary}"
case "${1:-}" in
  app)
    APP=dist/WindowPilot.app
    codesign --verify --deep --strict "$APP"
    codesign -dv "$APP" 2>&1 | grep 'Authority=Developer ID Application:' > /dev/null
    codesign -dv "$APP" 2>&1 | grep 'flags=.*runtime' > /dev/null
    # Recreate the upload from this exact app, never a stale build ZIP.
    ditto -c -k --sequesterRsrc --keepParent "$APP" dist/WindowPilot.zip
    xcrun notarytool submit dist/WindowPilot.zip --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" dist/WindowPilot.zip
    ;;
  dmg)
    codesign --verify --verbose=2 dist/WindowPilot.dmg
    codesign -dv dist/WindowPilot.dmg 2>&1 | grep 'Authority=Developer ID Application:' > /dev/null
    xcrun notarytool submit dist/WindowPilot.dmg --keychain-profile "$PROFILE" --wait
    xcrun stapler staple dist/WindowPilot.dmg
    xcrun stapler validate dist/WindowPilot.dmg
    spctl --assess --type open --context context:primary-signature --verbose=2 dist/WindowPilot.dmg
    ;;
  *) echo "Usage: $0 app|dmg" >&2; exit 2 ;;
esac
