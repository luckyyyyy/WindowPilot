# Validation

Version 1.4.4: 43 tests passed locally with Thread Sanitizer (34 core/input/search tests and 9 native-window cases). `scripts/test.sh` isolates each AppKit lifecycle case in a fresh process and requires a complete test summary; an early exit without test completion fails the run.


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

![Automatically downloaded update ready for installation](docs/images/updater.png)

The dynamic-height update was checked with 35 disposable fixture windows (`--window-count 35`). On a display with a 1410-point usable height, the overflowing panel stopped at 1128 points (80%). Filtering to 35 rows expanded to 1024 points without a scrollbar; narrowing to 9 results used 296 points, closing a selected fixture window shrank it to 268 points, and an empty search used 88 points. Deleting the unmatched query restored the list. The fixture was then quit through the selected-app action.

Automated tests cover ordering and Unicode search, window-role filtering, independent settings panels, process timeout backoff, incremental/full refresh merging, preference persistence, and selected-window close/quit handling.

The local-window regression suite repeatedly restores native windows and checks that background AX operations reject the application's own PID. The latency regression deliberately blocks the scanner and verifies that interactive actions can complete independently. Tests do not require Accessibility permission or manipulate user documents.

Manual development checks use the isolated `scripts/WindowFixture.swift` application: a document NSWindow, an independent settings NSPanel, a title-change button and optional save/cancel dialogs. Previous checks verified minimized-window restoration, independent settings visibility, title refresh, targeted close/quit and cancel handling.

A development-machine sample measured full scans around 54 ms and single-app incremental scans around 9 ms after removing repeated timeouts against windowless helpers. These are workload-specific API timings, not a performance guarantee or display-frame measurement. Native minimization animations still apply.

Physical-keyboard hold/release behavior, third-party apps, multiple displays, Spaces/fullscreen, secure input, sleep/wake and login startup need ongoing real-world coverage. Targeted UI automation is not equivalent to physical global keyboard testing. CI checks compilation, tests with Thread Sanitizer, both binary architectures, bundle signatures and DMG integrity; its artifacts are ad-hoc signed development builds.
