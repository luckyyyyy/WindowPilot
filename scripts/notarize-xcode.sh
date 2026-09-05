#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
ARCHIVE="$PROJECT_DIR/dist/WindowPilot.xcarchive"
case "${1:-}" in
  submit)
    : "${WINDOWPILOT_TEAM_ID:?Set the Apple Developer team ID}"
    : "${WINDOWPILOT_SIGN_IDENTITY:?Set a Developer ID Application identity}"
    [[ ! -e "$ARCHIVE" ]] || { echo "Archive already exists; preserve or move it before submitting a new build." >&2; exit 1; }
    codesign -dv dist/WindowPilot.app 2>&1 | grep 'flags=.*runtime' > /dev/null
    mkdir -p "$ARCHIVE/Products/Applications"
    ditto --norsrc --noextattr dist/WindowPilot.app "$ARCHIVE/Products/Applications/WindowPilot.app"
    codesign --verify --deep --strict "$ARCHIVE/Products/Applications/WindowPilot.app"
    export WINDOWPILOT_ARCHIVE="$ARCHIVE"
    python3 - <<'PY'
import datetime, os, pathlib, plistlib
archive = pathlib.Path(os.environ['WINDOWPILOT_ARCHIVE'])
with open('dist/WindowPilot.app/Contents/Info.plist', 'rb') as f:
    info = plistlib.load(f)
properties = {k: info[k] for k in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')}
properties.update(ApplicationPath='Applications/WindowPilot.app', Team=os.environ['WINDOWPILOT_TEAM_ID'], SigningIdentity=os.environ['WINDOWPILOT_SIGN_IDENTITY'])
with open(archive / 'Info.plist', 'wb') as f:
    plistlib.dump(dict(ArchiveVersion=2, CreationDate=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), Name='WindowPilot', SchemeName='WindowPilot', ApplicationProperties=properties), f)
with open('dist/ExportOptions.plist', 'wb') as f:
    plistlib.dump(dict(method='developer-id', destination='upload', teamID=os.environ['WINDOWPILOT_TEAM_ID'], signingStyle='automatic'), f)
PY
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath dist/notary-upload \
      -exportOptionsPlist dist/ExportOptions.plist -allowProvisioningUpdates
    echo 'Uploaded. After Apple finishes processing, run scripts/notarize-xcode.sh export.'
    ;;
  export)
    EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/windowpilot-notarized.XXXXXX")"
    trap 'rm -rf "$EXPORT_DIR"' EXIT
    xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR"
    xattr -dr com.apple.FinderInfo "$EXPORT_DIR/WindowPilot.app" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "$EXPORT_DIR/WindowPilot.app" 2>/dev/null || true
    xcrun stapler validate "$EXPORT_DIR/WindowPilot.app"
    codesign --verify --deep --strict "$EXPORT_DIR/WindowPilot.app"
    ditto --norsrc --noextattr "$EXPORT_DIR/WindowPilot.app" dist/WindowPilot.app
    ditto -c -k --sequesterRsrc --keepParent "$EXPORT_DIR/WindowPilot.app" dist/WindowPilot.zip
    ;;
  *) echo "Usage: $0 submit|export" >&2; exit 2 ;;
esac
