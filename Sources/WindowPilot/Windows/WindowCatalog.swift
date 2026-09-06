import AppKit
import ApplicationServices
import Synchronization

struct AppRecord: Sendable {
    let pid: pid_t
    let name: String
    let bundleID: String
    let hidden: Bool
    let regular: Bool
}

/// Scanning owns mutable catalog state. Interactive AX operations use a separate
/// serial queue and a published snapshot of remote handles. Snapshot locks only
/// copy references; they are never held across IPC. Own-process AX is forbidden.
final class WindowCatalog: @unchecked Sendable {
    private let scanQueue: DispatchQueue
    private let actionQueue: DispatchQueue
    // Remote element identity is immutable. Configure messaging timeouts before
    // publishing; scanner state and action history never mutate across queues.
    private struct Entry: @unchecked Sendable {
        let id: String
        let element: AXUIElement
        var lastUsed: UInt64
    }
    private let handles = Mutex<[String: Entry]>([:])
    private var entries: [pid_t: [Entry]] = [:]

    init(scanQueue: DispatchQueue = DispatchQueue(label: "WindowPilot.scan", qos: .utility),
         actionQueue: DispatchQueue = DispatchQueue(label: "WindowPilot.actions", qos: .userInteractive)) {
        self.scanQueue = scanQueue
        self.actionQueue = actionQueue
    }

    private func handle(for item: WindowItem) -> Entry? {
        handles.withLock { $0[item.id] }
    }

    private func publishHandles() {
        let snapshot = Dictionary(uniqueKeysWithValues: entries.values.flatMap { $0 }.map { ($0.id, $0) })
        handles.withLock { $0 = snapshot }
    }

    private var clock: UInt64 = 0
    private var lastFocusedID: String?
    private var appUsage: [pid_t: UInt64] = [:]
    private var cached: [pid_t: [WindowItem]] = [:]
    private var retryPolicy = ScanRetryPolicy()

    func invalidate(pid: pid_t) {
        scanQueue.async { [self] in retryPolicy.reset(pid: pid) }
    }

    func scan(apps: [AppRecord], frontPID: pid_t?, onlyPIDs: Set<pid_t>? = nil, completion: @escaping @MainActor @Sendable ([WindowItem]) -> Void) {
        let externalApps = apps.filter { $0.pid != ProcessInfo.processInfo.processIdentifier }
        scanQueue.async { [self] in
            SwitchTrace.mark(onlyPIDs == nil ? "scan.scope.full" : "scan.scope.incremental")
            SwitchTrace.mark("scan.started")
            let items = collect(apps: externalApps, frontPID: frontPID, onlyPIDs: onlyPIDs)
            publishHandles()
            SwitchTrace.mark("scan.finished")
            Task { @MainActor in completion(items) }
        }
    }

    private func collect(apps: [AppRecord], frontPID: pid_t?, onlyPIDs: Set<pid_t>?) -> [WindowItem] {
        let alive = Set(apps.map(\.pid))
        retryPolicy.retain(pids: alive)
        entries = entries.filter { alive.contains($0.key) }
        appUsage = appUsage.filter { alive.contains($0.key) }
        cached = cached.filter { alive.contains($0.key) }
        SwitchTrace.mark("scan.server.started")
        let serverWindows = Dictionary(grouping: ServerWindow.snapshot(), by: \.pid)
        SwitchTrace.mark("scan.server.finished")
        var result: [WindowItem] = []
        var diagnostics: [[String: Any]] = []
        for app in apps {
            if let onlyPIDs, !onlyPIDs.contains(app.pid), let existing = cached[app.pid] {
                result.append(contentsOf: existing)
                continue
            }
            guard ScanPolicy.shouldQuery(app: app, hasServerWindow: !(serverWindows[app.pid] ?? []).isEmpty,
                                         hasCachedWindow: !(entries[app.pid] ?? []).isEmpty) else {
                SwitchTrace.mark("scan.app.\(app.pid).skipped-service")
                continue
            }
            guard retryPolicy.shouldAttempt(app: app, now: ProcessInfo.processInfo.systemUptime, frontPID: frontPID) else {
                SwitchTrace.mark("scan.app.\(app.pid).backoff")
                result.append(contentsOf: cached[app.pid] ?? [])
                continue
            }
            SwitchTrace.mark("scan.app.\(app.pid).started")
            defer { SwitchTrace.mark("scan.app.\(app.pid).finished") }
            let axApp = AXUIElementCreateApplication(app.pid)
            // A hung app must not stall the switcher. This timeout is per AX request.
            AXUIElementSetMessagingTimeout(axApp, 0.08)
            var windowsValue: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
            SwitchTrace.mark("scan.app.\(app.pid).windows-status.\(status.rawValue)")
            if status == .cannotComplete {
                retryPolicy.failed(app: app, now: ProcessInfo.processInfo.systemUptime)
                // Keep existing handles until the process answers again.
                result.append(contentsOf: cached[app.pid] ?? [])
                continue
            }
            retryPolicy.reset(pid: app.pid)
            var windows = windowsValue as? [AXUIElement] ?? []
            let focused = element(axApp, kAXFocusedWindowAttribute)
            if let focused, string(focused, kAXRoleAttribute) == kAXWindowRole,
               !windows.contains(where: { CFEqual($0, focused) }) { windows.append(focused) }
            let previous = entries[app.pid] ?? []
            var next: [Entry] = []
            let resultStart = result.count
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.08)
                let role = string(window, kAXRoleAttribute)
                let subrole = string(window, kAXSubroleAttribute)
                let windowSize = size(window)
                if let windowSize, windowSize.width < 80 || windowSize.height < 45 { continue }
                let matches: [ServerWindow]
                if let position = position(window), let windowSize {
                    matches = (serverWindows[app.pid] ?? []).filter { $0.matches(CGRect(origin: position, size: windowSize)) }
                } else { matches = [] }
                let accepted = WindowPolicy.accepts(.init(role: role, subrole: subrole,
                    modal: bool(window, kAXModalAttribute), closable: element(window, kAXCloseButtonAttribute) != nil,
                    regularApp: app.regular, matchingLayers: matches.map(\.layer)))
                if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
                    diagnostics.append(["app": app.name, "title": string(window, kAXTitleAttribute), "role": role,
                        "subrole": subrole, "layers": matches.map(\.layer), "accepted": accepted,
                        "modal": bool(window, kAXModalAttribute), "closable": element(window, kAXCloseButtonAttribute) != nil,
                        "main": bool(window, kAXMainAttribute), "minimized": bool(window, kAXMinimizedAttribute)])
                }
                guard accepted else { continue }
                let title = WindowPolicy.title(axTitle: string(window, kAXTitleAttribute),
                    document: string(window, kAXDocumentAttribute), serverTitle: matches.first(where: { $0.layer == 0 })?.title ?? "", appName: app.name)
                var entry = previous.first(where: { CFEqual($0.element, window) })
                    ?? Entry(id: "\(app.pid)-\(UUID().uuidString)", element: window, lastUsed: 0)
                let isFocused = focused.map { CFEqual($0, window) } ?? false
                if app.pid == frontPID && isFocused && lastFocusedID != entry.id {
                    clock = DispatchTime.now().uptimeNanoseconds
                    entry.lastUsed = clock
                    lastFocusedID = entry.id
                }
                next.append(entry)
                result.append(WindowItem(id: entry.id, pid: app.pid, appName: app.name, bundleID: app.bundleID,
                                         title: title,
                                         minimized: bool(window, kAXMinimizedAttribute), hidden: app.hidden,
                                         isAppOnly: false, focused: isFocused, lastUsed: entry.lastUsed))
            }
            entries[app.pid] = next
            // Filtered-out overlay windows must not turn into a fake app-only entry.
            if windows.isEmpty && app.regular {
                let id = "app-\(app.pid)"
                if app.pid == frontPID && lastFocusedID != id { clock = DispatchTime.now().uptimeNanoseconds; lastFocusedID = id; appUsage[app.pid] = clock }
                result.append(WindowItem(id: id, pid: app.pid, appName: app.name, bundleID: app.bundleID,
                                         title: app.name, minimized: false, hidden: app.hidden,
                                         isAppOnly: true, focused: app.pid == frontPID,
                                         lastUsed: appUsage[app.pid] ?? 0))
            }
            cached[app.pid] = Array(result.dropFirst(resultStart))
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--diagnostics"), arguments.indices.contains(index + 1),
           let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
        }
        return WindowOrdering.sorted(result, frontPID: frontPID)
    }

    func restore(_ item: WindowItem, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard item.pid != ProcessInfo.processInfo.processIdentifier else {
            Task { @MainActor in completion(false) }
            return
        }
        SwitchTrace.mark("restore.queued")
        actionQueue.async { [self] in
            SwitchTrace.mark("restore.started")
            guard let entry = handle(for: item) else {
                Task { @MainActor in completion(item.isAppOnly) }
                return
            }
            // Check the handle is still valid before changing application focus.
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(entry.element, kAXRoleAttribute as CFString, &role) == .success else {
                Task { @MainActor in completion(false) }; return
            }
            if bool(entry.element, kAXMinimizedAttribute) {
                let status = AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                guard status == .success else { Task { @MainActor in completion(false) }; return }
            }
            SwitchTrace.mark("restore.finished")
            Task { @MainActor in completion(true) }
        }
    }

    func raise(_ item: WindowItem, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard item.pid != ProcessInfo.processInfo.processIdentifier else {
            Task { @MainActor in completion(false) }
            return
        }
        SwitchTrace.mark("raise.queued")
        actionQueue.async { [self] in
            SwitchTrace.mark("raise.started")
            guard let entry = handle(for: item) else {
                Task { @MainActor in completion(item.isAppOnly) }; return
            }
            let axApp = AXUIElementCreateApplication(item.pid)
            AXUIElementSetMessagingTimeout(axApp, 0.08)
            AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, entry.element)
            let raised = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString) == .success
            if raised {
                let usedAt = DispatchTime.now().uptimeNanoseconds
                scanQueue.async { [self] in
                    if let index = entries[item.pid]?.firstIndex(where: { $0.id == item.id }) {
                        entries[item.pid]?[index].lastUsed = usedAt
                    }
                    lastFocusedID = item.id
                }
            }
            SwitchTrace.mark("raise.finished")
            Task { @MainActor in completion(raised) }
        }
    }

    func close(_ item: WindowItem, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard item.pid != ProcessInfo.processInfo.processIdentifier, !item.isAppOnly else {
            Task { @MainActor in completion(false) }; return
        }
        actionQueue.async { [self] in
            guard let entry = handle(for: item),
                  let button = element(entry.element, kAXCloseButtonAttribute),
                  bool(button, kAXEnabledAttribute) else {
                Task { @MainActor in completion(false) }; return
            }
            // Press this window's standard close button; never synthesize a global Cmd-W.
            AXUIElementSetMessagingTimeout(button, 0.3)
            let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
            // A save sheet can make the AX reply time out after the press was
            // delivered. Inspect the window afterwards; never retry the press.
            let accepted = status == .success || status == .cannotComplete
            Task { @MainActor in completion(accepted) }
        }
    }

    func revealActionTarget(_ item: WindowItem) {
        guard item.pid != ProcessInfo.processInfo.processIdentifier else { return }
        actionQueue.async { [self] in
            let app = AXUIElementCreateApplication(item.pid)
            AXUIElementSetMessagingTimeout(app, 0.08)
            let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
            // Quit may put a save sheet on a different document from the selected row.
            let confirmation = windows.first { window in
                (value(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains {
                    string($0, kAXRoleAttribute) == kAXSheetRole || bool($0, kAXModalAttribute)
                }
            }
                ?? windows.first { bool($0, kAXModalAttribute) }
            guard let window = confirmation ?? handle(for: item)?.element else { return }
            if confirmation != nil { AXUIElementSetMessagingTimeout(window, 0.08) }
            if bool(window, kAXMinimizedAttribute) {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    /// nil means the app did not answer; a successful request does not prove closure.
    func isOpen(_ item: WindowItem, completion: @escaping @MainActor @Sendable (Bool?) -> Void) {
        guard item.pid != ProcessInfo.processInfo.processIdentifier, !item.isAppOnly else {
            Task { @MainActor in completion(nil) }; return
        }
        actionQueue.async { [self] in
            guard let entry = handle(for: item) else {
                Task { @MainActor in completion(false) }; return
            }
            let app = AXUIElementCreateApplication(item.pid)
            AXUIElementSetMessagingTimeout(app, 0.08)
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            let open: Bool? = status == .success
                ? (value as? [AXUIElement]).map { $0.contains { CFEqual($0, entry.element) } }
                : nil
            Task { @MainActor in completion(open) }
        }
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ attribute: String) -> String { value(element, attribute) as? String ?? "" }
    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool { value(element, attribute) as? Bool ?? false }
    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func size(_ window: AXUIElement) -> CGSize? {
        guard let value = value(window, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
    private func position(_ window: AXUIElement) -> CGPoint? {
        guard let value = value(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }
}

/// Notifications improve freshness; the slow reconciliation timer covers apps
/// that omit AX notifications. Observers are attached on the main run loop.
@MainActor
final class WindowObservers {
    private var observers: [pid_t: AXObserver] = [:]
    var onChange: ((pid_t) -> Void)?

    func update(pids: Set<pid_t>) {
        let pids = pids.subtracting([ProcessInfo.processInfo.processIdentifier])
        for pid in Array(observers.keys) where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
        for pid in pids where observers[pid] == nil {
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, element, notification, context in
                guard let context else { return }
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success else { return }
                SwitchTrace.mark("notify.\(pid).\(notification as String)")
                MainActor.assumeIsolated {
                    Unmanaged<WindowObservers>.fromOpaque(context).takeUnretainedValue().onChange?(pid)
                }
            }
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                         kAXApplicationActivatedNotification, kAXUIElementDestroyedNotification,
                         kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                         kAXTitleChangedNotification] {
                AXObserverAddNotification(observer, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            observers[pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
