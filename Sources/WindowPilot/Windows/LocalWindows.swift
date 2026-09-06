import AppKit
import Combine

/// Same-process AX calls invoke AppKit directly on the caller's thread.
/// Own windows therefore never enter the background AX catalog: use AppKit
/// references under MainActor for both reads and writes.
@MainActor
final class LocalWindows {
    static let settingsID = "local-settings"
    private weak var settings: NSWindow?
    private var lastUsed: UInt64 = 0
    private var wasFocused = false
    private var minimizing = false
    private var restoreAfterMinimize = false
    private var observations = Set<AnyCancellable>()
    private var activationRequest: UUID?
    private let isApplicationActive: () -> Bool
    private let requestApplicationActivation: (@escaping @MainActor (Bool) -> Void) -> Void

    init(isApplicationActive: @escaping () -> Bool = { NSApp.isActive },
         requestApplicationActivation: @escaping (@escaping @MainActor (Bool) -> Void) -> Void = { completion in
        // A global event tap/nonactivating panel does not grant cooperative activation.
        // Launch Services handles the explicit user request to open this accessory app.
        guard Bundle.main.bundleURL.pathExtension == "app" else { completion(false); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            let accepted = app != nil && error == nil
            Task { @MainActor in completion(accepted) }
        }
    }) {
        self.isApplicationActive = isApplicationActive
        self.requestApplicationActivation = requestApplicationActivation
    }

    func registerSettings(_ window: NSWindow) {
        observations.removeAll()
        cancelPendingActivation()
        settings = window
        minimizing = false
        restoreAfterMinimize = false
        NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification, object: window)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.minimizing = true }
            }.store(in: &observations)
        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification, object: window)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.minimizing = false
                    // Defer until AppKit has finished its minimize transaction.
                    Task { @MainActor [weak self] in
                        guard let self, self.restoreAfterMinimize else { return }
                        self.restoreAfterMinimize = false
                        self.activate(id: Self.settingsID)
                    }
                }
            }.store(in: &observations)
    }

    func snapshot(frontPID: pid_t?) -> [WindowItem] {
        guard let window = settings, window.isVisible || window.isMiniaturized else {
            wasFocused = false
            return []
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let focused = frontPID == pid && (window.isKeyWindow || window.isMainWindow)
        if focused && !wasFocused { lastUsed = DispatchTime.now().uptimeNanoseconds }
        wasFocused = focused
        return [WindowItem(id: Self.settingsID, pid: pid, appName: "WindowPilot",
                           bundleID: Bundle.main.bundleIdentifier ?? "local.windowpilot.app",
                           title: window.title, minimized: window.isMiniaturized, hidden: NSApp.isHidden,
                           isAppOnly: false, focused: focused, lastUsed: lastUsed)]
    }

    @discardableResult
    func close(id: String) -> Bool {
        guard id == Self.settingsID, let window = settings,
              window.isVisible || window.isMiniaturized, window.styleMask.contains(.closable) else { return false }
        cancelPendingActivation()
        window.performClose(nil) // Honor windowShouldClose and document save handling.
        return true
    }

    func cancelPendingActivation() {
        restoreAfterMinimize = false
        activationRequest = nil
    }

    @discardableResult
    func activate(id: String) -> Bool {
        guard id == Self.settingsID, let window = settings else { return false }
        if minimizing {
            restoreAfterMinimize = true
            return true
        }
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        // Visibility is not proof of activation. Request Launch Services activation
        // when another process still owns the foreground, and coalesce reopen events.
        if !isApplicationActive() && activationRequest == nil {
            let ticket = UUID()
            activationRequest = ticket
            requestApplicationActivation { [weak self, weak window] accepted in
                guard let self, self.activationRequest == ticket else { return }
                self.activationRequest = nil
                guard accepted, let window, window.isVisible, !window.isMiniaturized,
                      self.isApplicationActive() else { return }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                SwitchTrace.mark("local.activation.completed")
            }
        }
        lastUsed = DispatchTime.now().uptimeNanoseconds
        wasFocused = true
        return true
    }
}
