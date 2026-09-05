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
| `SwitcherLayout.swift` | Content height including search/empty state, capped at 80% of the current display’s usable height |
| `SettingsView.swift` | Native NavigationSplitView, grouped forms and exclusion editor |
| `Models.swift` | Ordering, filtering and persistent preferences |

The scan queue publishes immutable remote-window handle snapshots under a short-lived mutex. No IPC runs while holding that lock. Restore, raise and close run on a separate interaction queue, so a slow scan cannot delay a selected action. Recent-use mutations return to the scan queue.

AX notifications request a scan for the affected process. Requests merge without losing a pending full scan; periodic reconciliation runs every 2.5 seconds. Known windowless WebKit workers are skipped only when neither WindowServer nor the cache provides evidence of a real window. AX timeouts preserve previous windows and retry after 1, 2, 4, 8 and at most 15 seconds. Activation and window notifications allow immediate retries.

Own-process AX operations are rejected at the catalog boundary. `LocalWindows` reads and operates on native NSWindows on MainActor, respecting window delegates and minimization transactions.

Close uses the target's AX close button; quit requests normal NSRunningApplication termination. Neither force-quits an app. If an application shows a save confirmation or refuses an action, the switcher dismisses and activates it for the user to decide.

The default app does not log window titles or send network requests. Optional `--trace-switches /absolute/path/trace.log` records monotonic action/scan timings without titles. Timings describe API completion, not measured display latency.

## Updates

`AppUpdater` starts Sparkle 2.9.6 only after normal app launch. Its Combine bindings reflect Sparkle-owned persisted preferences and update-session availability. The main thread owns all updater and UI calls; test initialization does not start the updater. Sparkle handles HTTPS retrieval, signed appcast and archive verification, installation, rollback on failure, and relaunch.

The stable feed is the `appcast.xml` asset of the latest GitHub Release. Enclosures point to immutable versioned release URLs. Both the feed and the notarized DMG are EdDSA signed. Keys remain in the developer's Keychain. Developer ID signing preserves the app identity across replacement. CI embeds the pinned framework with its helper apps, signs each nested component, and verifies both architectures.

### Activating the application's own settings

The nonactivating switcher does not guarantee cooperative app activation. `LocalWindows` orders the selected settings window forward without changing its normal level, requests activation, and falls back to `NSWorkspace.openApplication` for the explicit user action if the app remains inactive. Reopen callbacks share one pending request, and cancelled requests cannot reorder windows after completion. Visibility alone is not treated as evidence that the foreground process changed.

### Search input mode

Each switcher session starts in window-action mode. X enters explicit search mode, including when Command is still held. Search mode consumes Q/W as text before shortcut dispatch; the controller also rejects selected-window actions while searching. Emptying the query keeps this mode active. Cancelling/committing resets it for the next session. The panel header and its height follow the mode flag, so the input prompt is visible before any query text is typed.
