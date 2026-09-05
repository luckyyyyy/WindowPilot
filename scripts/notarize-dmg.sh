#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${WINDOWPILOT_NOTARY_PROFILE:-WindowPilot-notary}"
codesign --verify --verbose=2 dist/WindowPilot.dmg
xcrun notarytool submit dist/WindowPilot.dmg --keychain-profile "$PROFILE" --wait
xcrun stapler staple dist/WindowPilot.dmg
xcrun stapler validate dist/WindowPilot.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 dist/WindowPilot.dmg
(cd dist && shasum -a 256 WindowPilot.dmg WindowPilot.zip > SHA256SUMS)
