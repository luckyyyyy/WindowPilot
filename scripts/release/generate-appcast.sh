#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ACCOUNT="${WINDOWPILOT_SPARKLE_ACCOUNT:-WindowPilot-G89F9A6472}"
TOOLS=.build/artifacts/sparkle/Sparkle/bin
EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Resources/Info.plist)
[[ "$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)" == "$EXPECTED_KEY" ]] || { echo 'Sparkle public key does not match this release.' >&2; exit 1; }
# Only include the final notarized DMG. Using a signed DMG also permits future key rotation.
codesign --verify --verbose=2 dist/WindowPilot.dmg
xcrun stapler validate dist/WindowPilot.dmg
FEED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/windowpilot-feed.XXXXXX")"
trap 'rm -rf "$FEED_DIR"' EXIT
cp dist/WindowPilot.dmg "$FEED_DIR/WindowPilot.dmg"
if [[ -n "${1:-}" ]]; then cp "$1" "$FEED_DIR/WindowPilot.md"; fi
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/luckyyyyy/WindowPilot/releases/download/v$VERSION/" \
  --link "https://github.com/luckyyyyy/WindowPilot" "$FEED_DIR"
cp "$FEED_DIR/appcast.xml" dist/appcast.xml
python3 scripts/release/verify-appcast.py dist/appcast.xml dist/WindowPilot.dmg
swift scripts/release/verify-update-signatures.swift dist/appcast.xml dist/WindowPilot.dmg Resources/Info.plist
(cd dist && shasum -a 256 WindowPilot.dmg WindowPilot.zip appcast.xml > SHA256SUMS)
