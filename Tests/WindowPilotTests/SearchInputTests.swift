import AppKit
import Testing
@testable import WindowPilot

@Suite(.serialized) @MainActor
struct SearchInputTests {
    private func setup() -> (SwitcherController, KeyboardInterceptor) {
        _ = NSApplication.shared
        let controller = SwitcherController()
        controller.presented = true
        controller.sessionItems = [WindowItem(id: "search-fixture", pid: -1, appName: "QQ",
            bundleID: "test.search", title: "QQWWXX", minimized: false, hidden: false,
            isAppOnly: false, focused: false, lastUsed: 0)]
        let keyboard = KeyboardInterceptor()
        keyboard.controller = controller
        return (controller, keyboard)
    }

    @discardableResult
    private func press(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = .command,
                       keyboard: KeyboardInterceptor) throws -> Bool {
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)?.cgEvent)
        let consumed = keyboard.handle(.keyDown, down) == nil
        let up = try #require(down.copy())
        up.type = .keyUp
        #expect((keyboard.handle(.keyUp, up) == nil) == consumed)
        return consumed
    }

    @Test func xEntersSearchWithoutBecomingPartOfTheQuery() throws {
        let (controller, keyboard) = setup()
        defer { controller.cancel() }
        try press("q", code: 12, modifiers: [], keyboard: keyboard)
        #expect(!controller.searching)
        #expect(controller.query.isEmpty)
        try press("x", code: 7, keyboard: keyboard)
        #expect(controller.searching)
        #expect(controller.query.isEmpty)
        #expect(controller.switcherLayout.searching) // Empty search must show its header.
        try press("q", code: 12, keyboard: keyboard)
        #expect(controller.query == "q")
        #expect(controller.selected?.appName == "QQ")
        #expect(!controller.actionInProgress)
    }

    @Test func commandQAndWAreTextInSearchWithOrWithoutCommandHeld() throws {
        for modifiers: NSEvent.ModifierFlags in [[], .command] {
            let (controller, keyboard) = setup()
            defer { controller.cancel() }
            try press("x", code: 7, modifiers: modifiers, keyboard: keyboard)
            for (text, code): (String, UInt16) in [("q", 12), ("q", 12), ("w", 13), ("w", 13), ("x", 7)] {
                try press(text, code: code, modifiers: modifiers, keyboard: keyboard)
                #expect(!controller.actionInProgress)
            }
            #expect(controller.query == "qqwwx")
            #expect(controller.presented)
        }
    }

    @Test func deletingAllTextKeepsSearchModeAndActionsDisabled() throws {
        let (controller, keyboard) = setup()
        defer { controller.cancel() }
        try press("x", code: 7, keyboard: keyboard)
        try press("q", code: 12, keyboard: keyboard)
        try press("\u{8}", code: 51, keyboard: keyboard)
        #expect(controller.query.isEmpty)
        #expect(controller.searching)
        controller.performSelectedAction(.closeWindow)
        controller.performSelectedAction(.quitApplication)
        #expect(!controller.actionInProgress)
        try press("w", code: 13, keyboard: keyboard)
        #expect(controller.query == "w")
        #expect(!controller.actionInProgress)
        try press("\u{1b}", code: 53, modifiers: [], keyboard: keyboard)
        #expect(!controller.presented)
        #expect(!controller.searching)
        #expect(controller.query.isEmpty)
        controller.presented = true
        try press("q", code: 12, modifiers: [], keyboard: keyboard)
        #expect(!controller.searching)
        #expect(controller.query.isEmpty)
    }

    @Test func searchNavigationAndEmptyQueryDoNotExitSearch() throws {
        let (controller, keyboard) = setup()
        defer { controller.cancel() }
        try press("X", code: 7, modifiers: [.command, .shift], keyboard: keyboard)
        try press("\t", code: 48, keyboard: keyboard)
        #expect(controller.searching)
        #expect(controller.query.isEmpty)
        #expect(!controller.actionInProgress)
    }
}
