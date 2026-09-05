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

## Notarize the final DMG

The outer signed DMG also needs notarization. Do not treat a successful assessment of the contained application as approval of the DMG. Configure an Apple notarytool Keychain profile interactively, then submit and staple the final image:

```sh
xcrun notarytool store-credentials WindowPilot-notary
./scripts/notarize-dmg.sh
```

Never put passwords, app-specific passwords, API keys or certificate exports into scripts, commits, issue comments or release assets.

## Sign the GitHub update feed

Sparkle 2.9.6 is pinned by `Package.resolved`. The build script embeds its universal framework, preserves symlinks, signs its nested helpers inside out, and includes the upstream license. Release apps keep hardened runtime and library validation. Ad-hoc CI apps omit hardened runtime because they have no Team ID for library validation.

The public EdDSA key is in `Resources/Info.plist`. The private key is kept only in the local login Keychain under account `WindowPilot-G89F9A6472`. Never export it into CI or the repository. Forks must generate their own key and change both the feed URL and signing account.

After notarizing and stapling the final DMG, generate and validate the feed:

```sh
./scripts/generate-appcast.sh release-notes.md
(cd dist && shasum -a 256 WindowPilot.dmg WindowPilot.zip appcast.xml > SHA256SUMS)
```

The script uses Sparkle's official generator and verifies its signed XML and DMG with CryptoKit using only the embedded public key. It also checks version, build number, system requirement, archive length, signature presence and version-specific download URL. Do not edit the generated XML without re-signing it. Upload `appcast.xml` and its exact final DMG together to a draft release, then publish it as latest. The application's feed URL is `https://github.com/luckyyyyy/WindowPilot/releases/latest/download/appcast.xml`. Never mark a release latest without its feed asset; never replace a release payload after signing its feed.

Before publication, test an updater-enabled older build against the new release, including downloading, installing, relaunching, version change and Accessibility trust. For a draft release this requires publishing the complete assets before checking through the production feed. A manual file copy does not count as an update test. Retain a notarized bootstrap app locally for future regression checks.

## Publish

Inspect screenshots for private window titles. Check the app inside the mounted DMG, its architectures, stapled ticket, and Gatekeeper assessment. Confirm that its version matches `Resources/Info.plist`, commit the exact source, and wait for a green CI run.

```sh
(cd dist && shasum -a 256 WindowPilot.dmg WindowPilot.zip > SHA256SUMS)
git tag vVERSION
git push origin vVERSION
gh release create vVERSION dist/WindowPilot.dmg dist/WindowPilot.zip dist/appcast.xml dist/SHA256SUMS \
  --title 'WindowPilot VERSION' --notes-file release-notes.md
```

Do not rebuild the app after notarizing it without resubmitting the changed build. CI artifacts must never overwrite the signed release assets.
