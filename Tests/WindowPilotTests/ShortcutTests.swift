import AppKit
import Testing
@testable import WindowPilot

@Suite(.serialized) @MainActor
struct ShortcutTests {
    private func event(_ key: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> CGEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
            isARepeat: false, keyCode: code)?.cgEvent)
    }
    private func preferences() throws -> (Preferences, UserDefaults, String) {
        let name = "WindowPilotShortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (Preferences(defaults: defaults), defaults, name)
    }

    @Test func persistsCustomBindingsAndMigratesExistingPreferences() throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(prefs.shortcuts == ShortcutConfiguration())
        prefs.compact = false
        prefs.shortcuts.allWindows = ShortcutBinding(keyCode: 48, key: "\t", flags: .maskAlternate)
        let restored = Preferences(defaults: defaults)
        #expect(restored.shortcuts.allWindows.display == "⌥Tab")
        #expect(!restored.compact)
        restored.shortcuts = ShortcutConfiguration()
        #expect(Preferences(defaults: defaults).shortcuts.allWindows.display == "⌘Tab")
        #expect(!Preferences(defaults: defaults).compact)
        defaults.set(Data("broken".utf8), forKey: "shortcuts")
        #expect(Preferences(defaults: defaults).shortcuts == ShortcutConfiguration())
    }

    @Test func rejectsDuplicateUnsafeAndReservedBindings() {
        let config = ShortcutConfiguration()
        #expect(config.isValid)
        #expect(config.validationError(config.quitApplication, for: .search) != nil)
        #expect(config.validationError(.init(keyCode: 0, key: "a", flags: []), for: .allWindows) != nil)
        #expect(config.validationError(.init(keyCode: 48, key: "\t", flags: [.maskAlternate, .maskShift]), for: .allWindows) != nil)
        #expect(config.validationError(.init(keyCode: 53, key: "", flags: .maskCommand), for: .closeWindow) != nil)
        #expect(config.validationError(.init(keyCode: 49, key: " ", flags: .maskCommand), for: .allWindows) != nil)
        #expect(config.validationError(.init(keyCode: 48, key: "\t", flags: .maskAlternate), for: .allWindows) == nil)
    }

    @Test func invalidStoredConfigurationFallsBackToDefaults() throws {
        let (_, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        var invalid = ShortcutConfiguration()
        invalid.search = invalid.closeWindow
        defaults.set(try JSONEncoder().encode(invalid), forKey: "shortcuts")
        #expect(Preferences(defaults: defaults).shortcuts == ShortcutConfiguration())
    }

    @Test func customActionRespectsModifiersAndKeyboardCharacters() throws {
        var config = ShortcutConfiguration()
        config.closeWindow = .init(keyCode: 15, key: "r", flags: .maskCommand)
        #expect(SelectedWindowAction.match(try event("r", code: 15, modifiers: .command), configuration: config) == .closeWindow)
        #expect(SelectedWindowAction.match(try event("w", code: 13, modifiers: .command), configuration: config) == nil)
        // Match character rather than US physical position; tolerate held Alt from Alt-Tab.
        #expect(SelectedWindowAction.match(try event("r", code: 0, modifiers: [.command, .option]), configuration: config, ignoring: .maskAlternate) == .closeWindow)
        #expect(SelectedWindowAction.match(try event("r", code: 15, modifiers: [.command, .shift]), configuration: config) == nil)
    }

    @Test func recordingSuppressesSwitcherAndSavesOnlyOnConfirmation() throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = SwitcherController()
        controller.preferences = prefs
        let keyboard = KeyboardInterceptor(); keyboard.controller = controller
        let recorder = controller.shortcutRecorder
        defer { recorder.stop() }
        recorder.begin(.allWindows, preferences: prefs)
        let down = try event("\t", code: 48, modifiers: .option)
        #expect(keyboard.handle(.keyDown, down) == nil)
        #expect(!controller.presented)
        #expect(recorder.candidate?.display == "⌥Tab")
        #expect(prefs.shortcuts.allWindows.display == "⌘Tab")
        let up = try #require(down.copy()); up.type = .keyUp
        #expect(keyboard.handle(.keyUp, up) == nil)
        recorder.save()
        #expect(prefs.shortcuts.allWindows.display == "⌥Tab")
        #expect(recorder.action == nil)
        recorder.begin(.allWindows, preferences: prefs)
        _ = recorder.handle(.keyDown, try event("e", code: 14, modifiers: .control))
        _ = recorder.handle(.keyDown, try event("\u{1b}", code: 53))
        #expect(recorder.action == nil)
        #expect(prefs.shortcuts.allWindows.display == "⌥Tab")
    }

    @Test func recordingConflictCannotSaveAndFocusLossCancels() throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let recorder = ShortcutRecorder()
        defer { recorder.stop() }
        recorder.begin(.search, preferences: prefs)
        _ = recorder.handle(.keyDown, try event("q", code: 12, modifiers: .command))
        #expect(recorder.error != nil)
        #expect(recorder.candidate == nil)
        recorder.save()
        #expect(prefs.shortcuts.search.display == "X")
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(recorder.action == nil)
    }

    @Test func customModifierControlsReleaseAndOldGlobalKeyPassesThrough() throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.shortcuts.allWindows = .init(keyCode: 48, key: "\t", flags: .maskAlternate)
        let controller = SwitcherController(); controller.preferences = prefs
        let keyboard = KeyboardInterceptor(); keyboard.controller = controller
        #expect(keyboard.handle(.keyDown, try event("\t", code: 48, modifiers: .command)) != nil)
        controller.presented = true; controller.heldCommand = true; controller.heldModifiers = .maskAlternate
        let flags = try event("", code: 58, modifiers: .option); flags.type = .flagsChanged
        _ = keyboard.handle(.flagsChanged, flags)
        #expect(controller.presented)
        flags.flags = []
        _ = keyboard.handle(.flagsChanged, flags)
        #expect(!controller.presented)
    }

    @Test func customPrefixAndGlobalLettersRemainTextInSearch() throws {
        let (prefs, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        prefs.shortcuts.search = .init(keyCode: 1, key: "s", flags: [])
        prefs.shortcuts.allWindows = .init(keyCode: 14, key: "e", flags: .maskAlternate)
        let controller = SwitcherController(); controller.preferences = prefs
        controller.presented = true; controller.heldCommand = true; controller.heldModifiers = .maskAlternate
        let keyboard = KeyboardInterceptor(); keyboard.controller = controller
        defer { controller.cancel() }
        _ = keyboard.handle(.keyDown, try event("x", code: 7, modifiers: .option))
        #expect(!controller.searching)
        _ = keyboard.handle(.keyDown, try event("S", code: 1, modifiers: [.option, .shift]))
        #expect(controller.searching)
        #expect(controller.query.isEmpty)
        _ = keyboard.handle(.keyDown, try event("e", code: 14, modifiers: .option))
        _ = keyboard.handle(.keyDown, try event("q", code: 12, modifiers: [.option, .command]))
        #expect(controller.query == "eq")
        #expect(!controller.actionInProgress)
    }
}
