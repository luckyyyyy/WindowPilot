#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
[[ -d dist/WindowPilot.app ]] || { echo 'Run scripts/build.sh first.' >&2; exit 1; }
if [[ ! -x .build/dmg-tools/bin/dmgbuild ]]; then
  PYTHON="${WINDOWPILOT_PYTHON:-python3}"
  if ! "$PYTHON" -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
    if [[ -x /opt/homebrew/bin/python3 ]]; then PYTHON=/opt/homebrew/bin/python3;
    elif [[ -x /usr/local/bin/python3 ]]; then PYTHON=/usr/local/bin/python3;
    else echo 'Python 3.10+ is required. Set WINDOWPILOT_PYTHON to its path.' >&2; exit 1; fi
  fi
  "$PYTHON" -m venv --clear .build/dmg-tools
  .build/dmg-tools/bin/python -m pip install --disable-pip-version-check -r scripts/dmg/dmg-requirements.txt
fi
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/windowpilot-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto --norsrc --noextattr dist/WindowPilot.app "$STAGING_DIR/WindowPilot.app"
codesign --verify --deep --strict "$STAGING_DIR/WindowPilot.app"
swift scripts/dmg/make-dmg-background.swift "$PROJECT_DIR/dist/dmg-background.tiff"
.build/dmg-tools/bin/dmgbuild -s scripts/dmg/dmg-settings.py -D app="$STAGING_DIR/WindowPilot.app" WindowPilot dist/WindowPilot.dmg
if [[ -n "${WINDOWPILOT_SIGN_IDENTITY:-}" && "$WINDOWPILOT_SIGN_IDENTITY" != '-' ]]; then
  codesign --force --timestamp --sign "$WINDOWPILOT_SIGN_IDENTITY" dist/WindowPilot.dmg
fi
hdiutil verify dist/WindowPilot.dmg
