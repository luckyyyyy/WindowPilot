import AppKit
import ApplicationServices
import Observation
import ServiceManagement
import SwiftUI

@MainActor @Observable
final class SwitcherController {
    static let shared = SwitcherController()
    var preferences = Preferences()
    var items: [WindowItem] = []
    var sessionItems: [WindowItem] = [] { didSet { cachedSearch = nil } }
    var selectedIndex = 0
    var query = "" { didSet { cachedSearch = nil } }
    private(set) var searching = false
    var presented = false
    var heldCommand = false
    var trusted = false
    var keyboardReady = false
    var scanning = false
    private(set) var actionInProgress = false
    @ObservationIgnored private var releaseAfterAction = false
    var lastError: String?
    var loginEnabled = SMAppService.mainApp.status == .enabled
    var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    var lastScanDuration = 0.0
    var lastRefresh: Date?
    var availableApps: [AppChoice] = []
    @ObservationIgnored private let catalog = WindowCatalog()
    @ObservationIgnored private let localWindows = LocalWindows()
    @ObservationIgnored private let observers = WindowObservers()
    @ObservationIgnored private let keyboard = KeyboardInterceptor()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var panel: SwitcherPanel?
    @ObservationIgnored private(set) var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var icons: [pid_t: NSImage] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingScan: ScanScope?
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private var cachedSearch: [WindowSearchResult]?
    var searchResults: [WindowSearchResult] {
        // Read observed inputs even on cache hits so SwiftUI keeps tracking them.
        let items = sessionItems
        let text = query
        if let cachedSearch { return cachedSearch }
        let results = WindowSearch.results(items, query: text)
        cachedSearch = results
        return results
    }
    var filteredItems: [WindowItem] { searchResults.map(\.item) }
    var selected: WindowItem? {
        let filtered = filteredItems
        return filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }
    var statusText: String {
        if !trusted { return "需要辅助功能权限" }
        if !preferences.enabled { return "已暂停 · 使用系统切换器" }
        if !keyboardReady { return "快捷键尚未就绪" }
        return "已就绪 · ⌘Tab 切换窗口"
    }

    func start() {
        guard timer == nil else { return }
        keyboard.controller = self
        observers.onChange = { [weak self] pid in
            self?.catalog.invalidate(pid: pid)
            self?.scheduleRefresh(pid: pid)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                SwitchTrace.mark("workspace.\(name.rawValue)")
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        reconcile()
        if !trusted || !UserDefaults.standard.bool(forKey: "onboarded") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "onboarded")
        }
    }

    func reconcile() {
        let wasTrusted = trusted
        trusted = AXIsProcessTrusted()
        if trusted && preferences.enabled {
            if !keyboard.running { keyboardReady = keyboard.start() }
        } else {
            if keyboard.running || wasTrusted { keyboard.stop() }
            keyboardReady = false
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        if trusted { refresh() }
        else { items = []; observers.update(pids: []) }
        // Secure Input or sleep may hide a modifier-release event.
        if presented && heldCommand && !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) {
            if actionInProgress { releaseAfterAction = true }
            else { cancel() }
        }
    }

    func scheduleRefresh(pid: pid_t? = nil) {
        let request: ScanScope = pid.map { .apps([$0]) } ?? .all
        pendingScan = pendingScan.map { $0.merging(request) } ?? request
        armRefresh()
    }

    private func armRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.runRefresh()
        }
    }

    func refresh() {
        pendingScan = .all
        runRefresh()
    }

    private func runRefresh() {
        guard trusted, !scanning, let scope = pendingScan else { return }
        pendingScan = nil
        scanning = true
        let start = Date()
        let systemOverlays: Set<String> = ["com.apple.notificationcenterui", "com.apple.controlcenter", "com.apple.dock",
                                           "com.apple.systemuiserver", "com.apple.loginwindow", "com.apple.Spotlight"]
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.activationPolicy != .prohibited
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && !systemOverlays.contains($0.bundleIdentifier ?? "")
        }
        var apps: [AppRecord] = []
        availableApps = Dictionary(grouping: running.compactMap { app -> AppChoice? in
            guard let id = app.bundleIdentifier, app.activationPolicy == .regular else { return nil }
            return AppChoice(id: id, name: app.localizedName ?? id)
        }, by: \.id).compactMap { $0.value.first }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        icons = icons.filter { pid, _ in running.contains { $0.processIdentifier == pid } }
        for app in running {
            apps.append(AppRecord(pid: app.processIdentifier, name: app.localizedName ?? "Application",
                                  bundleID: app.bundleIdentifier ?? "", hidden: app.isHidden,
                                  regular: app.activationPolicy == .regular))
            if icons[app.processIdentifier] == nil { icons[app.processIdentifier] = app.icon }
        }
        observers.update(pids: Set(apps.map(\.pid)))
        catalog.scan(apps: apps, frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, onlyPIDs: scope.pids) { [weak self] items in
            guard let self else { return }
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            self.items = WindowOrdering.sorted(items + self.localWindows.snapshot(frontPID: frontPID), frontPID: frontPID)
            self.scanning = false
            self.lastScanDuration = Date().timeIntervalSince(start)
            self.lastRefresh = Date()
            if self.pendingScan != nil { self.armRefresh() }
        }
    }

    func icon(for item: WindowItem) -> NSImage {
        if item.pid == ProcessInfo.processInfo.processIdentifier { return NSApp.applicationIconImage }
        return icons[item.pid] ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: item.appName)!
    }

    @discardableResult
    func begin(sameApp: Bool = false, reverse: Bool = false, heldCommand: Bool = false) -> Bool {
        guard !actionInProgress else { return false }
        guard trusted && keyboardReady else { if !heldCommand { showSettings() }; return false }
        generation += 1
        activationTask?.cancel()
        localWindows.cancelPendingActivation()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Read our own window state on MainActor, including a just-minimized settings window.
        items.removeAll { $0.pid == ProcessInfo.processInfo.processIdentifier }
        items += localWindows.snapshot(frontPID: frontPID)
        sessionItems = WindowOrdering.sorted(items.filter { preferences.accepts($0) && (!sameApp || $0.pid == frontPID) }, frontPID: frontPID)
        guard !sessionItems.isEmpty else { scheduleRefresh(); return false }
        query = ""
        searching = false
        self.heldCommand = heldCommand
        selectedIndex = heldCommand ? (reverse ? sessionItems.count - 1 : (sessionItems.count > 1 ? 1 : 0)) : 0
        presented = true
        if panel == nil { panel = SwitcherPanel(controller: self) }
        panel?.show(layout: switcherLayout)
        scheduleRefresh()
        return true
    }

    var switcherLayout: SwitcherLayout {
        SwitcherLayout(rowCount: filteredItems.count, compact: preferences.compact, searching: searching)
    }

    func resizePanel() {
        guard presented else { return }
        panel?.resize(layout: switcherLayout)
    }

    func move(_ delta: Int) { guard !actionInProgress else { return }; selectedIndex = WindowOrdering.nextIndex(selectedIndex, count: filteredItems.count, delta: delta) }
    func beginSearch() {
        guard presented, !actionInProgress, !searching else { return }
        searching = true
        query = ""
        selectedIndex = 0
    }
    func appendQuery(_ text: String) { guard presented, searching, !actionInProgress else { return }; query += text; selectedIndex = 0 }
    func deleteQuery() { guard searching, !actionInProgress else { return }; if !query.isEmpty { query.removeLast(); selectedIndex = 0 } }
    func select(_ item: WindowItem) { guard !actionInProgress else { return }; if let index = filteredItems.firstIndex(where: { $0.id == item.id }) { selectedIndex = index; commit() } }
    func containsMouse() -> Bool { panel?.frame.contains(NSEvent.mouseLocation) ?? false }

    func cancel() {
        presented = false
        panel?.orderOut(nil)
        query = ""
        searching = false
    }

    func commandReleased() {
        if actionInProgress { releaseAfterAction = true }
        else { commit() }
    }

    func commit() {
        guard !actionInProgress else { return }
        SwitchTrace.mark("commit")
        refreshTask?.cancel()
        let target = selected
        cancel()
        guard let target else { return }
        activate(target)
    }

    private func activate(_ target: WindowItem) {
        generation += 1
        let ticket = generation
        localWindows.cancelPendingActivation()
        if target.pid == ProcessInfo.processInfo.processIdentifier {
            lastError = localWindows.activate(id: target.id) ? nil : "这个窗口已关闭，请重新打开设置。"
            scheduleRefresh()
            return
        }
        catalog.restore(target) { [weak self] restored in
            guard let self, self.generation == ticket else { return }
            guard restored, let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else {
                self.lastError = "这个窗口已关闭或暂时无法恢复，请重新打开切换列表。"
                NSSound.beep(); self.scheduleRefresh(); return
            }
            SwitchTrace.mark("activation.started")
            app.unhide()
            // macOS 14+ cooperative activation; no deprecated ignoringOtherApps flag.
            NSApp.activate()
            NSApp.yieldActivation(to: app)
            let activated = app.activate(from: .current, options: [])
            SwitchTrace.mark("activation.finished")
            if target.isAppOnly {
                if let url = app.bundleURL {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
                }
                self.scheduleRefresh()
                return
            }
            self.catalog.raise(target) { [weak self] raised in
                guard let self, self.generation == ticket else { return }
                if !raised || !activated { self.lastError = "应用暂未确认窗口置前；如未切出，请再试一次。" }
                else { self.lastError = nil }
            }
            // Ordinary windows have already been raised; no delayed second raise.
            guard target.minimized else { self.scheduleRefresh(); return }
            self.activationTask = Task { [weak self] in
                // The Dock's restore animation can overwrite the first raise.
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self, self.generation == ticket,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return }
                self.catalog.raise(target) { _ in }
                self.scheduleRefresh()
            }
        }
    }

    func performSelectedAction(_ action: SelectedWindowAction) {
        guard presented, !searching, !actionInProgress, let target = selected else { return }
        guard action != .closeWindow || !target.isAppOnly else { NSSound.beep(); return }
        actionInProgress = true
        releaseAfterAction = false
        generation += 1
        activationTask?.cancel()
        localWindows.cancelPendingActivation()
        // Exit the event-tap callback before AppKit/AX work can trigger a modal loop.
        Task { [weak self] in
            guard let self else { return }
            let own = target.pid == ProcessInfo.processInfo.processIdentifier
            let app = NSRunningApplication(processIdentifier: target.pid)
            let validApp = app.map { !$0.isTerminated && ($0.bundleIdentifier == target.bundleID || target.bundleID.isEmpty) } ?? false
            let accepted: Bool
            switch action {
            case .closeWindow:
                if own { accepted = self.localWindows.close(id: target.id) }
                else {
                    accepted = await withCheckedContinuation { continuation in
                        self.catalog.close(target) { continuation.resume(returning: $0) }
                    }
                }
            case .quitApplication:
                if own {
                    self.cancel()
                    self.actionInProgress = false
                    NSApp.terminate(nil)
                    return
                }
                accepted = validApp && (app?.terminate() ?? false)
            }
            guard accepted else {
                self.actionInProgress = false
                self.lastError = action == .closeWindow ? "窗口未接受关闭请求。" : "应用未接受退出请求。"
                NSSound.beep()
                if self.releaseAfterAction { self.cancel() }
                self.scheduleRefresh()
                return
            }
            var completed = false
            // Preserve the list until the target has actually closed. Apps may ask
            // about unsaved work or decline quit, so never remove on request alone.
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(150))
                if action == .quitApplication { completed = app?.isTerminated ?? true }
                else if own { completed = !self.localWindows.snapshot(frontPID: nil).contains { $0.id == target.id } }
                else if app?.isTerminated == true { completed = true }
                else {
                    let open: Bool? = await withCheckedContinuation { continuation in
                        self.catalog.isOpen(target) { continuation.resume(returning: $0) }
                    }
                    completed = open == false
                }
                if completed { break }
            }
            self.actionInProgress = false
            self.lastError = nil
            if completed {
                let removed: (WindowItem) -> Bool = { action == .quitApplication ? $0.pid == target.pid : $0.id == target.id }
                self.sessionItems.removeAll(where: removed)
                self.items.removeAll(where: removed)
                self.selectedIndex = min(self.selectedIndex, max(0, self.filteredItems.count - 1))
                if self.filteredItems.isEmpty || self.releaseAfterAction { self.cancel() }
            } else if self.presented {
                // A save sheet, a refusal, or a slow response: show the target so
                // the user can handle its own dialog. Do not resend the action.
                self.cancel()
                if own { self.localWindows.activate(id: target.id) }
                else if let app, !app.isTerminated {
                    app.unhide()
                    NSApp.activate()
                    NSApp.yieldActivation(to: app)
                    app.activate(from: .current, options: [])
                    self.catalog.revealActionTarget(target)
                }
            }
            self.scheduleRefresh()
        }
    }

    func setEnabled(_ enabled: Bool) { preferences.enabled = enabled; reconcile() }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        openPrivacy()
    }

    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
            lastError = nil
        } catch { lastError = "无法更新开机启动：\(error.localizedDescription)" }
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(controller: self)
            if let window = settingsWindow?.window { localWindows.registerSettings(window) }
        }
        localWindows.activate(id: LocalWindows.settingsID)
        scheduleRefresh()
    }

    func stop() { keyboard.stop(); timer?.invalidate(); timer = nil; observers.update(pids: []) }
}
