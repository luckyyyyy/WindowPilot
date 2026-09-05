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
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, swallowedKeys.remove(code) != nil { actionKeys.remove(code); return nil }
        if type == .flagsChanged {
            if controller.presented && controller.heldCommand && !event.flags.contains(.maskCommand) { controller.commandReleased() }
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
        let command = event.flags.contains(.maskCommand)
        let reverse = event.flags.contains(.maskShift)
        let shortcut = command && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskControl)
        if shortcut && (code == 48 || (code == 50 && controller.preferences.sameAppShortcut)) && controller.preferences.enabled {
            if !controller.presented {
                guard controller.begin(sameApp: code == 50, reverse: reverse, heldCommand: true) else {
                    return Unmanaged.passUnretained(event)
                }
            } else { controller.move(reverse ? -1 : 1) }
            swallowedKeys.insert(code)
            return nil
        }
        guard controller.presented else { return Unmanaged.passUnretained(event) }
        if let action = SelectedWindowAction.match(event) {
            let firstPress = !swallowedKeys.contains(code) && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
            swallowedKeys.insert(code)
            actionKeys.insert(code)
            if firstPress { controller.performSelectedAction(action) }
            return nil
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
                controller.appendQuery(characters)
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
