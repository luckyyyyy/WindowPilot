# Validation

Version 1.5.1: 51 tests passed locally with Thread Sanitizer (42 core/input/search/shortcut tests and 9 native-window cases). `scripts/test.sh` isolates each AppKit lifecycle case in a fresh process and requires a complete test summary; an early exit without test completion fails the run.


## Directory cleanup and pointer feedback, 1.5.1

Source files are now grouped by responsibility and the mixed `Models.swift` has been separated into window models/ordering and settings preferences/rules. Panel, row rendering and search highlighting have dedicated files. Build/test entry points remain stable; release, DMG, asset-generation and test-fixture helpers have dedicated directories. The old Xcode notarization flow is replaced by one Keychain-backed notarytool entry point for app and DMG. Feed generation cleans its temporary directory and writes one checksum manifest after signing all assets; rebuilding removes the previous generated bundle before copying the new one.

All 51 tests pass with Thread Sanitizer after the moves. Shell entry points pass syntax validation. The independent row preview uses the shipping `SwitcherRow` with sample titles and was inspected in Aqua and Dark Aqua: row spacing, selected color and labels remain intact. The switcher itself retains its dark appearance in both modes.

Hover is row-local, uses 10% neutral white over the dark background, resets on disappearance and never changes keyboard selection. Selected rows keep the system selection color. The panel explicitly accepts mouse movement. The native automation host delivered synthetic mouseMoved events but did not produce SwiftUI tracking callbacks, so this is **not** evidence of physical pointer enter/exit behavior; that interaction remains a manual verification item.

![Shipping rows in the isolated dark preview; keyboard selection shown](images/row-preview-dark.png)

## Configurable shortcuts and native proportions, 1.5.0

Eight new cases verify preference migration and persistence, restoring defaults without resetting unrelated settings, rejecting invalid saved configurations and overlapping bindings, custom action modifiers and keyboard-layout characters, recording without triggering the switcher, explicit Save versus Escape cancellation, focus-loss cancellation, modifier-release confirmation after switching from Command to Option, and search text taking priority over printable shortcuts.

A signed development build was exercised through its actual settings: recorded and saved Option-Tab; attempted Command-Q for search and saw the conflict with Quit plus disabled Save; cancelled with Escape; and restored defaults. No user windows were closed by this test. Settings proportions were compared with macOS System Settings: native mini switches, small buttons with 13-point labels, 20-point sidebar icons and compact sidebar rows. No scaled custom switch drawing is used.

The final mini switches were inspected on General, Windows and About alongside macOS System Settings; the rule editor's native fields and paired buttons were also checked and cancelled. Production Sparkle then updated `/Applications/WindowPilot.app` from 1.4.4 to 1.5.0. The installed executable matches the published build, nested signatures and the stapled ticket validate, and accessibility/login/compact settings remain enabled. Shortcut defaults were restored after testing. Release commit `880874b` passed CI run `34004617038`.

## Fuzzy search, 1.4.4

Eight new cases cover ordered subsequences (`ws` → `watchOptions`), case-invariant scores/order, exact/prefix/contiguous ranking, better alignments after an early weak match, multiword matches across visible fields, stable session-order ties, Unicode folding and original grapheme offsets, attributed-text preservation, cache invalidation after query/title changes, and long or impossible queries. The existing X-prefix and Q/W action-isolation tests also pass with fuzzy results.

An optimized local benchmark of 200 synthetic windows with mixed English/Chinese titles completed 20 uncached searches in 143 ms (about 7 ms per search). This measures matching only, not a display-frame or third-party-window timing guarantee; navigation uses cached results.

Live UI verification after the production Sparkle update from 1.4.3 to 1.4.4: a disposable `watchOptions` window appears for `ws`; the original `w` and `s` are highlighted on both selected and unselected rows. Replacing the query with `WS` preserves the same result order. The installed executable matches the released executable, its nested signature and stapled ticket validate, and Accessibility remains authorized. The fixture was closed after testing. Release commit `934fe79` passed GitHub Actions run `34003449899`.

## Explicit search mode, 1.4.3

Regression tests send paired key-down/key-up events through the real `KeyboardInterceptor.handle` entry point. They verify: ordinary letters do not start searching; X enters search without entering the prefix into the query; `xq` matches QQ while Command remains held; Q/W/X input works with and without Command; deleting the last character keeps search mode active and window actions disabled; Escape clears both query and mode; and navigation preserves search. The empty search header is driven by mode rather than non-empty query. Existing selected-window action tests continue to cover normal-mode Cmd-W and modifier matching for Cmd-Q.

These are programmatic native event tests, not a physical keyboard or live UI automation test.

## Own settings activation regression, 1.4.2

The 1.4.1 failure was reproduced by selecting WindowPilot's own settings from its nonactivating switcher. An independent read-only window-order monitor showed ChatGPT remained frontmost and settings stayed behind it. The previous tests checked visibility, which did not establish foreground activation.

With 1.4.2, the same selection from Finder switched the actual foreground process to WindowPilot and placed settings before Finder in the normal window layer. Explicit ordering is followed by a Launch Services activation request when cooperative activation has not taken effect. Pending reopen requests are coalesced; cancelled callbacks cannot raise stale selections. No floating or always-on-top level is used.

New native tests cover unconditional ordering, reopen coalescing, cancellation and minimizing/restoring the settings window through the same activation path. The minimize regression verifies `isMiniaturized` before selecting and both restored visibility and normal level afterward. UI automation can itself send reopen events while inspecting minimized windows, so the minimization assertion uses direct in-process AppKit state rather than treating an inspection-triggered reopen as a successful switch.

## GitHub automatic update, 2026-09-05

Verified with the production GitHub Releases feed and Developer ID signed, notarized apps. An internal updater-enabled 1.4.0 (build 9) was installed once to bootstrap the test. Its update-check timestamp was cleared to trigger the normal scheduled check on the next launch; the 24-hour interval itself was not waited out.

- At 15:40 local time, 1.4.0 automatically fetched the signed feed and downloaded the 1.4.1 DMG in the background. Sparkle logged valid EdDSA signatures for both feed and update.
- Opening “检查更新…” showed **1.4.1 already downloaded and ready to install**. Choosing the native “安装并重启应用” button replaced the app in `/Applications` and relaunched it. No manual copy of 1.4.1 was used.
- The application changed from 1.4.0 (9), PID 13245, to 1.4.1 (10), PID 13463. Its executable hash matched the published build; strict nested code-signature verification, stapled ticket validation and Gatekeeper assessment passed.
- Accessibility remained authorized, the switcher reported ready, and login, compact rows, automatic checks and automatic downloads remained enabled.
- A subsequent update check reported “WindowPilot 1.4.1是当前的最新版本。”
- All four settings pages and the rule sheet were inspected. Text action buttons use equal label widths and native regular controls; add/remove icon buttons and sheet action pairs match. First opening the rule sheet now enables Add for its selected app, invalid regex disables it, and clearing the regex restores it. Test inputs were cancelled without saving a rule.

The release feed and DMG were independently verified using CryptoKit and the embedded public key. Disposable tampering tests rejected a modified feed and modified payload. Signed production artifacts and the exact feed are hosted together in release `v1.4.1`; release code passed GitHub Actions run `33952887996`.

![Automatically downloaded update ready for installation](images/updater.png)

The dynamic-height update was checked with 35 disposable fixture windows (`--window-count 35`). On a display with a 1410-point usable height, the overflowing panel stopped at 1128 points (80%). Filtering to 35 rows expanded to 1024 points without a scrollbar; narrowing to 9 results used 296 points, closing a selected fixture window shrank it to 268 points, and an empty search used 88 points. Deleting the unmatched query restored the list. The fixture was then quit through the selected-app action.

Automated tests cover ordering and Unicode search, window-role filtering, independent settings panels, process timeout backoff, incremental/full refresh merging, preference persistence, and selected-window close/quit handling.

The local-window regression suite repeatedly restores native windows and checks that background AX operations reject the application's own PID. The latency regression deliberately blocks the scanner and verifies that interactive actions can complete independently. Tests do not require Accessibility permission or manipulate user documents.

Manual development checks use the isolated `scripts/testing/WindowFixture.swift` application: a document NSWindow, an independent settings NSPanel, a title-change button and optional save/cancel dialogs. Previous checks verified minimized-window restoration, independent settings visibility, title refresh, targeted close/quit and cancel handling.

A development-machine sample measured full scans around 54 ms and single-app incremental scans around 9 ms after removing repeated timeouts against windowless helpers. These are workload-specific API timings, not a performance guarantee or display-frame measurement. Native minimization animations still apply.

Physical-keyboard hold/release behavior, third-party apps, multiple displays, Spaces/fullscreen, secure input, sleep/wake and login startup need ongoing real-world coverage. Targeted UI automation is not equivalent to physical global keyboard testing. CI checks compilation, tests with Thread Sanitizer, both binary architectures, bundle signatures and DMG integrity; its artifacts are ad-hoc signed development builds.
