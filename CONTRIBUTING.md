# Contributing

Use macOS 26+ and Xcode 26+. Open `Package.swift` in Xcode or build from the terminal.

```sh
./scripts/test.sh
WINDOWPILOT_SIGN_IDENTITY=- ./scripts/build.sh --universal
./scripts/build-dmg.sh
```

Keep cross-process Accessibility calls off the main thread. Never query or mutate this application's own windows through Accessibility: use `LocalWindows` on `MainActor`. Event-tap callbacks must not wait for scanning or IPC. Preserve an application's normal save/cancel flow when closing windows or quitting.

Add a regression test for behavioral fixes. For UI changes, include a screenshot and check both system appearances. Describe what you actually tested; synthetic key events do not prove physical global shortcut behavior.

Do not commit signing credentials, user preferences, window-title logs, crash reports containing personal information, or generated bundles. CI builds do not need developer credentials.
