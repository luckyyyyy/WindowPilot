import AppKit
import Testing
@testable import WindowPilot

@Suite(.serialized) @MainActor
struct LocalWindowsTests {
    private func makeWindow() -> NSWindow {
        TestApplication.prepare()
        NSApp.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 320, height: 160),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "WindowPilot Main-thread Regression"
        return window
    }

    @Test func repeatedlyRestoresOwnWindowThroughAppKitOnMainThread() {
        let window = makeWindow()
        defer { window.close() }
        let local = LocalWindows()
        local.registerSettings(window)
        let pid = ProcessInfo.processInfo.processIdentifier
        for _ in 0..<100 {
            window.orderOut(nil)
            #expect(local.snapshot(frontPID: pid).isEmpty)
            #expect(local.activate(id: LocalWindows.settingsID))
            #expect(Thread.isMainThread)
            #expect(window.isVisible)
            #expect(local.snapshot(frontPID: pid).first?.title == window.title)
        }
        #expect(!local.activate(id: "unknown-window"))
    }

    @Test func ownWindowIsExplicitlyRaisedAndActivationRequestsAreCoalesced() {
        TestApplication.prepare()
        let window = RaiseRecordingWindow(contentRect: NSRect(x: 120, y: 120, width: 320, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var requests = 0
        var finish: (@MainActor (Bool) -> Void)?
        var active = false
        let local = LocalWindows(isApplicationActive: { active }, requestApplicationActivation: { completion in
            requests += 1
            finish = completion
        })
        local.registerSettings(window)
        #expect(local.activate(id: LocalWindows.settingsID))
        #expect(window.unconditionalRaises > 0)
        #expect(requests == 1)
        // Launch Services delivers reopen to this same app; it must not start a loop.
        #expect(local.activate(id: LocalWindows.settingsID))
        #expect(requests == 1)
        let raisedBeforeCompletion = window.unconditionalRaises
        active = true
        finish?(true)
        #expect(window.unconditionalRaises > raisedBeforeCompletion)
        #expect(window.level == .normal) // Never turn settings into an always-on-top window.
    }

    @Test func cancelledOwnActivationCannotRaiseAStaleWindow() {
        TestApplication.prepare()
        let window = RaiseRecordingWindow(contentRect: NSRect(x: 120, y: 120, width: 320, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var finish: (@MainActor (Bool) -> Void)?
        var active = false
        let local = LocalWindows(isApplicationActive: { active }, requestApplicationActivation: { finish = $0 })
        local.registerSettings(window)
        #expect(local.activate(id: LocalWindows.settingsID))
        local.cancelPendingActivation() // A newer selection or close supersedes this request.
        let raisedBeforeCompletion = window.unconditionalRaises
        active = true
        finish?(true)
        #expect(window.unconditionalRaises == raisedBeforeCompletion)
    }

    @Test func restoresMinimizedSettingsThroughTheSameActivationPath() async throws {
        let window = makeWindow()
        defer { window.close() }
        let local = LocalWindows(requestApplicationActivation: { $0(true) })
        local.registerSettings(window)
        window.makeKeyAndOrderFront(nil)
        window.miniaturize(nil)
        for _ in 0..<60 where !window.isMiniaturized { try await Task.sleep(for: .milliseconds(50)) }
        #expect(window.isMiniaturized)
        #expect(local.activate(id: LocalWindows.settingsID))
        for _ in 0..<60 where window.isMiniaturized { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!window.isMiniaturized)
        #expect(window.isVisible)
        #expect(window.level == .normal)
    }

    @Test func backgroundCatalogRejectsOwnProcessForReadsAndWrites() async {
        let window = makeWindow()
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let pid = ProcessInfo.processInfo.processIdentifier
        let catalog = WindowCatalog()
        let ownApp = AppRecord(pid: pid, name: "WindowPilot", bundleID: "local.windowpilot.app", hidden: false, regular: true)
        let items: [WindowItem] = await withCheckedContinuation { continuation in
            catalog.scan(apps: [ownApp], frontPID: pid) { continuation.resume(returning: $0) }
        }
        #expect(items.isEmpty)
        // An app-only entry would previously be accepted even for the current process.
        let ownItem = WindowItem(id: "app-\(pid)", pid: pid, appName: "WindowPilot", bundleID: "local.windowpilot.app",
                                 title: window.title, minimized: false, hidden: false, isAppOnly: true, focused: true, lastUsed: 0)
        let restored: Bool = await withCheckedContinuation { continuation in
            catalog.restore(ownItem) { continuation.resume(returning: $0) }
        }
        let raised: Bool = await withCheckedContinuation { continuation in
            catalog.raise(ownItem) { continuation.resume(returning: $0) }
        }
        let closed: Bool = await withCheckedContinuation { continuation in
            catalog.close(ownItem) { continuation.resume(returning: $0) }
        }
        #expect(!closed)
        #expect(window.isVisible)
        #expect(!restored)
        #expect(!raised)
    }

    @Test func switcherCommitUsesTheLocalWindowPath() throws {
        TestApplication.prepare()
        NSApp.setActivationPolicy(.accessory)
        let controller = SwitcherController()
        controller.showSettings()
        let window = try #require(controller.settingsWindow?.window)
        defer { window.close(); controller.stop() }
        let item = WindowItem(id: LocalWindows.settingsID, pid: ProcessInfo.processInfo.processIdentifier,
                              appName: "WindowPilot", bundleID: "local.windowpilot.app", title: window.title,
                              minimized: false, hidden: false, isAppOnly: false, focused: false, lastUsed: 0)
        // Test the real commit entry point, not just the local-window helper.
        for _ in 0..<25 {
            window.orderOut(nil)
            controller.sessionItems = [item]
            controller.selectedIndex = 0
            controller.commit()
            #expect(window.isVisible)
            #expect(controller.lastError == nil)
        }
    }

    @Test func selectedCloseUsesOwnWindowPathAndSwallowsRepeatsAfterDismissal() async throws {
        TestApplication.prepare()
        let controller = SwitcherController()
        controller.showSettings()
        let window = try #require(controller.settingsWindow?.window)
        defer { window.close(); controller.stop() }
        let item = WindowItem(id: LocalWindows.settingsID, pid: ProcessInfo.processInfo.processIdentifier,
                              appName: "WindowPilot", bundleID: "local.windowpilot.app", title: window.title,
                              minimized: false, hidden: false, isAppOnly: false, focused: false, lastUsed: 0)
        controller.sessionItems = [item]
        controller.presented = true
        controller.heldCommand = true
        let keyboard = KeyboardInterceptor()
        keyboard.controller = controller
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w",
            isARepeat: false, keyCode: 13)?.cgEvent)
        #expect(keyboard.handle(.keyDown, down) == nil)
        #expect(controller.actionInProgress)
        #expect(controller.query.isEmpty)
        controller.commandReleased() // Must not commit a stale target while close is pending.
        for _ in 0..<30 where controller.actionInProgress { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!window.isVisible)
        #expect(!controller.presented)
        #expect(controller.sessionItems.isEmpty)
        // A held key must not leak to whatever app is now in front.
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(keyboard.handle(.keyDown, down) == nil)
        let up = try #require(down.copy())
        up.type = .keyUp
        #expect(keyboard.handle(.keyUp, up) == nil)
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        #expect(keyboard.handle(.keyDown, down) != nil)
    }

    @Test func closeHonorsWindowDelegateAndLeavesOtherWindowsOpen() {
        let selected = makeWindow()
        let other = makeWindow()
        let delegate = CloseVeto()
        selected.delegate = delegate
        selected.makeKeyAndOrderFront(nil)
        other.makeKeyAndOrderFront(nil)
        defer { selected.close(); other.close() }
        let local = LocalWindows()
        local.registerSettings(selected)
        #expect(local.close(id: LocalWindows.settingsID))
        #expect(delegate.calledOnMainThread)
        #expect(selected.isVisible) // The app declined close, e.g. an unsaved document.
        #expect(other.isVisible)
        delegate.allowClose = true
        #expect(local.close(id: LocalWindows.settingsID))
        #expect(!selected.isVisible)
        #expect(other.isVisible)
    }

    @Test func actionKeysRespectModifiersAndEmptySelection() throws {
        TestApplication.prepare()
        let controller = SwitcherController()
        controller.presented = true
        let keyboard = KeyboardInterceptor()
        keyboard.controller = controller
        for (letter, expected) in [("w", SelectedWindowAction.closeWindow), ("q", .quitApplication)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: 0, context: nil, characters: letter, charactersIgnoringModifiers: letter,
                isARepeat: false, keyCode: letter == "w" ? 13 : 12)?.cgEvent)
            #expect(SelectedWindowAction.match(event) == expected)
            #expect(keyboard.handle(.keyDown, event) == nil)
            #expect(!controller.actionInProgress)
            #expect(controller.query.isEmpty)
            for flags: CGEventFlags in [[], .maskShift, [.maskCommand, .maskShift], [.maskCommand, .maskAlternate], [.maskCommand, .maskControl]] {
                event.flags = flags
                #expect(SelectedWindowAction.match(event) == nil)
            }
        }
    }

}


@MainActor private final class CloseVeto: NSObject, NSWindowDelegate {
    var allowClose = false
    var calledOnMainThread = false
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        calledOnMainThread = Thread.isMainThread
        return allowClose
    }
}

// AppKit/SwiftUI may request termination when a test closes the final window.
// Keep the test host alive so Swift Testing can report every result and exit status.
@MainActor private final class TestApplication: NSObject, NSApplicationDelegate {
    static let delegate = TestApplication()
    static func prepare() {
        _ = NSApplication.shared
        NSApp.delegate = delegate
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}

@MainActor private final class RaiseRecordingWindow: NSWindow {
    var unconditionalRaises = 0
    override func orderFrontRegardless() {
        unconditionalRaises += 1
        super.orderFrontRegardless()
    }
}
