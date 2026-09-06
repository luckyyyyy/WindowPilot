import AppKit
import ApplicationServices

@MainActor
final class KeyboardInterceptor {
    weak var controller: SwitcherController?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var swallowedKeys = Set<Int64>()
    private var actionKeys = Set<Int64>()
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return running }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let consumed = MainActor.assumeIsolated {
                let owner = Unmanaged<KeyboardInterceptor>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type, event) == nil
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let cgEvent = event.cgEvent else { return false }
                return self.handle(cgEvent.type, cgEvent) == nil
            }
            return consumed ? nil : event
        }
        return running
    }

    func stop() {
        controller?.cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        tap = nil; source = nil; swallowedKeys.removeAll(); actionKeys.removeAll()
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            controller?.cancel()
            swallowedKeys.removeAll(); actionKeys.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let controller else { return Unmanaged.passUnretained(event) }
        if controller.shortcutRecorder.handle(type, event) { return nil }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, swallowedKeys.remove(code) != nil { actionKeys.remove(code); return nil }
        if type == .flagsChanged {
            if controller.presented && controller.heldCommand && event.flags.intersection(controller.heldModifiers) != controller.heldModifiers { controller.commandReleased() }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            if controller.presented && !controller.containsMouse() { controller.cancel() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        // Keep swallowing a held action key even after its action dismisses the panel.
        // Otherwise keyboard auto-repeat could close an unrelated foreground window.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 && swallowedKeys.contains(code)
            && actionKeys.contains(code) { return nil }
        let shortcuts = controller.preferences.shortcuts
        let globalAction = [ShortcutAction.allWindows, .appWindows].first { action in
            if action == .appWindows && !controller.preferences.sameAppShortcut { return false }
            let binding = shortcuts[action]
            // Printable keys remain text once search has started.
            if controller.searching && ShortcutBinding.specialKeys[binding.keyCode] == nil { return false }
            return binding.matches(event) || binding.reversed.matches(event)
        }
        if let globalAction, controller.preferences.enabled {
            let binding = shortcuts[globalAction]
            let reverse = binding.reversed.matches(event)
            if !controller.presented {
                controller.heldModifiers = binding.flags
                guard controller.begin(sameApp: globalAction == .appWindows, reverse: reverse, heldCommand: true) else {
                    return Unmanaged.passUnretained(event)
                }
            } else { controller.move(reverse ? -1 : 1) }
            swallowedKeys.insert(code)
            return nil
        }
        guard controller.presented else { return Unmanaged.passUnretained(event) }
        let held = controller.heldCommand ? controller.heldModifiers : CGEventFlags.maskCommand
        if !controller.searching {
            let action = SelectedWindowAction.match(event, configuration: shortcuts, ignoring: held)
            if let action {
                let firstPress = !swallowedKeys.contains(code) && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
                swallowedKeys.insert(code)
                actionKeys.insert(code)
                if firstPress { controller.performSelectedAction(action) }
                return nil
            }
            if shortcuts.search.matches(event, ignoring: held.union(.maskShift)) {
                controller.beginSearch()
                swallowedKeys.insert(code)
                return nil
            }
        }
        switch code {
        case 53: controller.cancel()
        case 36, 76: controller.commit()
        case 125, 124, 48: controller.move(1)
        case 126, 123: controller.move(-1)
        case 51, 117: controller.deleteQuery()
        default:
            if let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
               !characters.isEmpty,
               characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
                if controller.searching {
                    // Command can remain held while searching; Q/W are text here.
                    controller.appendQuery(characters)
                }
            } else {
                // Let unrelated shortcuts through after dismissing the switcher.
                controller.cancel()
                return Unmanaged.passUnretained(event)
            }
        }
        swallowedKeys.insert(code)
        return nil
    }
}
