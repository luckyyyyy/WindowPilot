import AppKit
import Observation

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case allWindows, appWindows, closeWindow, quitApplication, search
    var id: Self { self }
    var title: String {
        switch self {
        case .allWindows: "切换所有窗口"
        case .appWindows: "切换当前应用的窗口"
        case .closeWindow: "关闭选中的窗口"
        case .quitApplication: "退出选中窗口所属应用"
        case .search: "进入搜索"
        }
    }
    var isGlobal: Bool { self == .allWindows || self == .appWindows }
}

struct ShortcutBinding: Codable, Equatable, Sendable {
    let keyCode: Int64
    let key: String
    let modifiers: UInt64
    static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
    var display: String {
        modifierSymbols + (Self.specialKeys[keyCode] ?? key.uppercased())
    }
    var modifierSymbols: String {
        [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
    }
    static let specialKeys: [Int64: String] = [48: "Tab", 49: "Space", 36: "Return", 76: "Enter",
        53: "Esc", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]

    init(keyCode: Int64, key: String, flags: CGEventFlags) {
        self.keyCode = keyCode; self.key = key.lowercased()
        modifiers = flags.intersection(Self.modifierMask).rawValue
    }
    init?(event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if event.flags.contains(.maskSecondaryFn) && !(Self.specialKeys[code]?.hasPrefix("F") ?? false) { return nil }
        let text = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
        guard Self.specialKeys[code] != nil || (text.count == 1 && text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700
        }) else { return nil }
        self.init(keyCode: code, key: text, flags: event.flags)
    }
    func matches(_ event: CGEvent, ignoring: CGEventFlags = []) -> Bool {
        guard let candidate = Self(event: event) else { return false }
        let ignored = ignoring.subtracting(flags)
        return sameKey(as: candidate) && candidate.flags.subtracting(ignored) == flags
    }
    func sameKey(as other: Self) -> Bool {
        if Self.specialKeys[keyCode] != nil || Self.specialKeys[other.keyCode] != nil { return keyCode == other.keyCode }
        return key == other.key
    }
    var reversed: Self { Self(keyCode: keyCode, key: key, flags: flags.union(.maskShift)) }
}

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    var allWindows = ShortcutBinding(keyCode: 48, key: "\t", flags: .maskCommand)
    var appWindows = ShortcutBinding(keyCode: 50, key: "`", flags: .maskCommand)
    var closeWindow = ShortcutBinding(keyCode: 13, key: "w", flags: .maskCommand)
    var quitApplication = ShortcutBinding(keyCode: 12, key: "q", flags: .maskCommand)
    var search = ShortcutBinding(keyCode: 7, key: "x", flags: [])
    subscript(_ action: ShortcutAction) -> ShortcutBinding {
        get {
            switch action {
            case .allWindows: allWindows
            case .appWindows: appWindows
            case .closeWindow: closeWindow
            case .quitApplication: quitApplication
            case .search: search
            }
        }
        set {
            switch action {
            case .allWindows: allWindows = newValue
            case .appWindows: appWindows = newValue
            case .closeWindow: closeWindow = newValue
            case .quitApplication: quitApplication = newValue
            case .search: search = newValue
            }
        }
    }
    func validationError(_ binding: ShortcutBinding, for action: ShortcutAction) -> String? {
        guard (0...127).contains(binding.keyCode), binding.modifiers == binding.flags.intersection(ShortcutBinding.modifierMask).rawValue,
              ShortcutBinding.specialKeys[binding.keyCode] != nil || binding.key.count == 1 else { return "请选择一个普通按键或功能键。" }
        if [53, 36, 76, 51, 117, 123, 124, 125, 126].contains(binding.keyCode) { return "Esc、确认、删除和方向键保留给列表操作。" }
        if action.isGlobal {
            if binding.flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty { return "切换快捷键需要包含 ⌘、⌥ 或 ⌃。" }
            if binding.flags.contains(.maskShift) { return "⇧ 用于反向切换，请选择不含 ⇧ 的组合。" }
        } else if binding.keyCode == 48 { return "Tab 保留给列表导航。" }
        if binding.flags.contains(.maskCommand) && binding.keyCode == 49 { return "⌘Space 保留给系统搜索，请选择其他组合。" }
        for other in ShortcutAction.allCases where other != action {
            let existing = self[other]
            guard binding.sameKey(as: existing) else { continue }
            // Local actions also accept the held global modifiers. Conservatively
            // reject overlapping keys so entering search can never become a close.
            if !action.isGlobal || !other.isGlobal || binding.flags == existing.flags {
                return "与“\(other.title)”冲突，请选择其他按键。"
            }
        }
        return nil
    }
    var isValid: Bool { ShortcutAction.allCases.allSatisfy { validationError(self[$0], for: $0) == nil } }
}

@MainActor @Observable
final class ShortcutRecorder {
    var action: ShortcutAction?
    private(set) var candidate: ShortcutBinding?
    private(set) var error: String?
    @ObservationIgnored private var resignToken: NSObjectProtocol?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var preferences: Preferences?
    @ObservationIgnored private var swallowed: Set<Int64> = []

    func begin(_ action: ShortcutAction, preferences: Preferences) {
        stop()
        self.preferences = preferences
        self.action = action
        resignToken = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let cg = event.cgEvent else { return event }
            let consumed = MainActor.assumeIsolated { self?.handle(cg.type, cg) == true }
            return consumed ? nil : event
        }
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp && swallowed.remove(code) != nil { return true }
        guard let action else { return false }
        if type == .flagsChanged { return true }
        guard type == .keyDown else { return false }
        swallowed.insert(code)
        if code == 53 { stop(); return true }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
        guard let binding = ShortcutBinding(event: event) else { error = "请选择一个普通按键或功能键。"; candidate = nil; return true }
        error = preferences?.shortcuts.validationError(binding, for: action)
        candidate = error == nil ? binding : nil
        return true
    }
    func save() {
        guard let action, let candidate, let preferences,
              preferences.shortcuts.validationError(candidate, for: action) == nil else { return }
        preferences.shortcuts[action] = candidate
        stop()
    }
    func stop() {
        action = nil; candidate = nil; error = nil; preferences = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
    }
}
