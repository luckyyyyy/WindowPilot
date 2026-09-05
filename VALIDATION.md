# Validation

Version 1.3.1: 28 tests passed locally with Thread Sanitizer (22 core tests and 6 native-window cases). `scripts/test.sh` isolates each AppKit lifecycle case in a fresh process and requires a complete test summary; an early exit without test completion fails the run.

The dynamic-height update was checked with 35 disposable fixture windows (`--window-count 35`). On a display with a 1410-point usable height, the overflowing panel stopped at 1128 points (80%). Filtering to 35 rows expanded to 1024 points without a scrollbar; narrowing to 9 results used 296 points, closing a selected fixture window shrank it to 268 points, and an empty search used 88 points. Deleting the unmatched query restored the list. The fixture was then quit through the selected-app action.

Automated tests cover ordering and Unicode search, window-role filtering, independent settings panels, process timeout backoff, incremental/full refresh merging, preference persistence, and selected-window close/quit handling.

The local-window regression suite repeatedly restores native windows and checks that background AX operations reject the application's own PID. The latency regression deliberately blocks the scanner and verifies that interactive actions can complete independently. Tests do not require Accessibility permission or manipulate user documents.

Manual development checks use the isolated `scripts/WindowFixture.swift` application: a document NSWindow, an independent settings NSPanel, a title-change button and optional save/cancel dialogs. Previous checks verified minimized-window restoration, independent settings visibility, title refresh, targeted close/quit and cancel handling.

A development-machine sample measured full scans around 54 ms and single-app incremental scans around 9 ms after removing repeated timeouts against windowless helpers. These are workload-specific API timings, not a performance guarantee or display-frame measurement. Native minimization animations still apply.

Physical-keyboard hold/release behavior, third-party apps, multiple displays, Spaces/fullscreen, secure input, sleep/wake and login startup need ongoing real-world coverage. Targeted UI automation is not equivalent to physical global keyboard testing. CI checks compilation, tests with Thread Sanitizer, both binary architectures, bundle signatures and DMG integrity; its artifacts are ad-hoc signed development builds.
