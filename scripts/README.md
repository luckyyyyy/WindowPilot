# Project scripts

Run these from the repository root. Build and test entry points stay in `scripts/`; their implementation assets live in subdirectories.

| Entry point | Purpose |
| --- | --- |
| `./scripts/test.sh` | Thread Sanitizer tests, with isolated AppKit lifecycle processes |
| `./scripts/build.sh [--universal]` | Compile, bundle Sparkle and sign the app/ZIP in `dist/` |
| `./scripts/build-dmg.sh` | Build the installer using `dmg/` settings, pinned requirements and background renderer |
| `./scripts/release/notarize.sh app` | Submit the app ZIP via a Keychain profile, staple the app and recreate the distribution ZIP |
| `./scripts/release/notarize.sh dmg` | Submit and staple the final signed DMG |
| `./scripts/release/generate-appcast.sh [notes.md]` | Sign and verify the feed/payload, then generate all release checksums |

`release/verify-appcast.py` and `release/verify-update-signatures.swift` are called by the feed generator. The former Xcode archive upload/export flow has been replaced by `release/notarize.sh`, using the same notarytool Keychain profile for the app and DMG. Full publishing instructions are in [RELEASING.md](../docs/RELEASING.md).

`assets/make-icon.swift` remains useful for regenerating the committed application icon:

```sh
mkdir -p dist
swift scripts/assets/make-icon.swift dist/WindowPilot.iconset
iconutil -c icns dist/WindowPilot.iconset -o dist/WindowPilotIcon.icns
```

`testing/WindowFixture.swift` is a disposable native window fixture for manual close, minimize, search and save/cancel checks. It is not part of the shipping application. `testing/preview-switcher.sh` opens the shipping row and native glass surface in a transparent borderless panel over a safe sample backdrop; it neither scans nor operates on user windows. Pass `--light` for Aqua; the default is Dark Aqua. Single-window captures may omit the compositor's behind-window glass effect, so inspect the live panel for actual transparency and blur.
