#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="$PWD/.build/previews/WindowPilotPreview.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.windowpilot.preview</string>
<key>CFBundleName</key><string>WindowPilotPreview</string>
<key>CFBundleExecutable</key><string>WindowPilotPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc -parse-as-library \
  Sources/WindowPilot/Windows/WindowModels.swift \
  Sources/WindowPilot/Switcher/WindowSearch.swift \
  Sources/WindowPilot/Switcher/SearchHighlight.swift \
  Sources/WindowPilot/Switcher/SwitcherRow.swift \
  scripts/testing/SwitcherPreview.swift -o "$APP/Contents/MacOS/WindowPilotPreview"
exec "$APP/Contents/MacOS/WindowPilotPreview" "$@"
