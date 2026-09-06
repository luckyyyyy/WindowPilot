# Release builds

CI produces universal, ad-hoc signed development artifacts. Public releases are built locally with a Developer ID Application certificate. Both the app and final signed DMG are notarized using a notarytool Keychain profile. No signing private keys are stored in this repository or required by CI.

## Signing setup

In Xcode → Settings → Apple Accounts, choose the publishing team and create or install a Developer ID Application certificate with its private key. Preserve existing certificates used by other apps. Set the signing identity and, if necessary, configure the notarytool profile interactively:

```sh
export WINDOWPILOT_SIGN_IDENTITY='Developer ID Application: YOUR COMPANY (TEAMID)'
# One-time setup only, if the profile does not already exist:
xcrun notarytool store-credentials WindowPilot-notary
```

The default profile is `WindowPilot-notary`; override it with `WINDOWPILOT_NOTARY_PROFILE`. Never put passwords, app-specific passwords, API keys or certificate exports into scripts, commits, issue comments or release assets.

## Build and notarize

Update both version fields in `Resources/Info.plist`, write release notes, then run:

```sh
./scripts/test.sh
./scripts/build.sh --universal
./scripts/release/notarize.sh app
./scripts/build-dmg.sh
./scripts/release/notarize.sh dmg
```

The app step creates the upload ZIP from the exact built app, waits for Apple, staples the app and recreates the ZIP with its offline ticket. The DMG step submits and staples the final signed image. Both steps verify Gatekeeper acceptance. If Apple processing is interrupted, inspect the submission status before retrying. Do not rebuild or alter a notarized app without resubmitting it.

Sparkle 2.9.6 is pinned by `Package.resolved`. The build script embeds its universal framework, preserves symlinks, signs nested helpers inside out and includes the upstream license. Release apps keep hardened runtime and library validation. Ad-hoc CI apps omit hardened runtime because they have no Team ID for library validation.

## Sign and validate the update feed

The public EdDSA key is in `Resources/Info.plist`. The private key remains in the local login Keychain under account `WindowPilot-G89F9A6472`. Never export it into CI or the repository. Forks must generate their own key and change the feed URL and signing account.

```sh
./scripts/release/generate-appcast.sh dist/release-notes.md
(cd dist && shasum -a 256 -c SHA256SUMS)
```

The generator uses Sparkle's official tooling, verifies signed XML and DMG with CryptoKit using the embedded public key, and checks version, build, system requirement, length and versioned download URL. It creates `SHA256SUMS` for the final DMG, ZIP and signed appcast together. Do not edit XML or payloads after signing.

## Publish and update the local app

Inspect screenshots for private window titles. Mount the final DMG and check its contained app's version, both architectures, strict signature, stapled ticket and Gatekeeper assessment. Commit the exact source and wait for green CI before publishing.

```sh
git tag vVERSION
git push origin vVERSION
gh release create vVERSION dist/WindowPilot.dmg dist/WindowPilot.zip dist/appcast.xml dist/SHA256SUMS \
  --draft --title 'WindowPilot VERSION' --notes-file dist/release-notes.md
# Check that all four assets are present, then publish the complete release:
gh release edit vVERSION --draft=false --latest
```

The stable feed is `https://github.com/luckyyyyy/WindowPilot/releases/latest/download/appcast.xml`. Never mark a release latest without its feed asset, and never replace a payload after signing its feed. CI artifacts must not overwrite signed release assets.

After publishing the complete assets, use an installed updater-enabled older build to check the production feed, download, install and relaunch. Verify the version, executable hash and Accessibility trust. A manual file copy does not count as an updater test. Preserve user settings and retain a notarized bootstrap app locally for future regression checks. Record actual verification in [VALIDATION.md](VALIDATION.md).
