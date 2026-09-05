# Architecture

WindowPilot uses public macOS APIs and has no runtime package dependencies.

| File | Responsibility |
| --- | --- |
| `WindowCatalog.swift` | Remote AX window handles, background scan queue, independent interactive action queue |
| `ScanPolicy.swift` | Helper-process filtering, timeout backoff, merging incremental refresh requests |
| `WindowPolicy.swift` | Window roles, layers and title fallback |
| `LocalWindows.swift` | MainActor AppKit operations on WindowPilot's own windows |
| `SwitcherController.swift` | Cached list, selection session, permissions and activation |
| `KeyboardInterceptor.swift` | Global event tap and local key handling |
| `SelectedWindowAction.swift` | Selected-window close/quit key matching |
| `SwitcherView.swift` | Nonactivating panel and compact searchable rows |
| `SettingsView.swift` | Native NavigationSplitView, grouped forms and exclusion editor |
| `Models.swift` | Ordering, filtering and persistent preferences |

The scan queue publishes immutable remote-window handle snapshots under a short-lived mutex. No IPC runs while holding that lock. Restore, raise and close run on a separate interaction queue, so a slow scan cannot delay a selected action. Recent-use mutations return to the scan queue.

AX notifications request a scan for the affected process. Requests merge without losing a pending full scan; periodic reconciliation runs every 2.5 seconds. Known windowless WebKit workers are skipped only when neither WindowServer nor the cache provides evidence of a real window. AX timeouts preserve previous windows and retry after 1, 2, 4, 8 and at most 15 seconds. Activation and window notifications allow immediate retries.

Own-process AX operations are rejected at the catalog boundary. `LocalWindows` reads and operates on native NSWindows on MainActor, respecting window delegates and minimization transactions.

Close uses the target's AX close button; quit requests normal NSRunningApplication termination. Neither force-quits an app. If an application shows a save confirmation or refuses an action, the switcher dismisses and activates it for the user to decide.

The default app does not log window titles or send network requests. Optional `--trace-switches /absolute/path/trace.log` records monotonic action/scan timings without titles. Timings describe API completion, not measured display latency.
