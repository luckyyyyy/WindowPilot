# Release builds

CI produces universal, ad-hoc signed development artifacts. Public releases are built locally with a Developer ID Application certificate, notarized through the signed-in Xcode account, then packaged in a signed DMG. No signing private keys are stored in this repository or required by CI.

## Sign and notarize the application

In Xcode → Settings → Apple Accounts, choose the publishing team and create or install a Developer ID Application certificate with its private key. Preserve existing certificates used by other apps. Set your own identity and team ID:

```sh
export WINDOWPILOT_SIGN_IDENTITY='Developer ID Application: YOUR COMPANY (TEAMID)'
export WINDOWPILOT_TEAM_ID='TEAMID'
./scripts/test.sh
./scripts/build.sh --universal
./scripts/notarize-xcode.sh submit
```

Once Apple finishes processing (check Xcode Organizer if needed):

```sh
./scripts/notarize-xcode.sh export
./scripts/build-dmg.sh
xcrun stapler validate dist/WindowPilot.app
spctl --assess --type execute --verbose=2 dist/WindowPilot.app
codesign --verify --verbose=2 dist/WindowPilot.dmg
```

The script uses `xcodebuild -exportArchive` with Developer ID upload, then `-exportNotarizedApp`. It does not extract account passwords or export private keys. `dist/WindowPilot.zip` and the DMG contain the stapled application. Preserve or move the previous `.xcarchive` before submitting a new build.

## Optional: notarize the DMG itself

A signed DMG containing a notarized and stapled app can distribute that app. To staple a separate ticket to the outer DMG too, configure an Apple notarytool Keychain profile interactively and submit the finished image:

```sh
xcrun notarytool store-credentials WindowPilot-notary
xcrun notarytool submit dist/WindowPilot.dmg --keychain-profile WindowPilot-notary --wait
xcrun stapler staple dist/WindowPilot.dmg
xcrun stapler validate dist/WindowPilot.dmg
```

Never put passwords, app-specific passwords, API keys or certificate exports into scripts, commits, issue comments or release assets.

## Publish

Inspect screenshots for private window titles. Check the app inside the mounted DMG, its architectures, stapled ticket, and Gatekeeper assessment. Confirm that its version matches `Resources/Info.plist`, commit the exact source, and wait for a green CI run.

```sh
(cd dist && shasum -a 256 WindowPilot.dmg WindowPilot.zip > SHA256SUMS)
git tag vVERSION
git push origin vVERSION
gh release create vVERSION dist/WindowPilot.dmg dist/WindowPilot.zip dist/SHA256SUMS \
  --title 'WindowPilot VERSION' --notes-file release-notes.md
```

Do not rebuild the app after notarizing it without resubmitting the changed build. CI artifacts must never overwrite the signed release assets.
