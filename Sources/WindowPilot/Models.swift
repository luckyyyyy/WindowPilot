import AppKit
import Observation

struct WindowItem: Identifiable, Sendable, Equatable {
    let id: String
    let pid: pid_t
    let appName: String
    let bundleID: String
    let title: String
    let minimized: Bool
    let hidden: Bool
    let isAppOnly: Bool
    let focused: Bool
    let lastUsed: UInt64

    var initial: String { String(appName.prefix(1)).lowercased() }
}

struct AppChoice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ExclusionRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var titlePattern: String

    func matches(_ item: WindowItem) -> Bool {
        guard item.bundleID == bundleID else { return false }
        if titlePattern.isEmpty { return true }
        return item.title.range(of: titlePattern, options: .regularExpression) != nil
    }
}

enum WindowOrdering {
    static func sorted(_ items: [WindowItem], frontPID: pid_t?) -> [WindowItem] {
        items.sorted {
            let lhsCurrent = $0.pid == frontPID && $0.focused
            let rhsCurrent = $1.pid == frontPID && $1.focused
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            if $0.lastUsed != $1.lastUsed { return $0.lastUsed > $1.lastUsed }
            if ($0.pid == frontPID) != ($1.pid == frontPID) { return $0.pid == frontPID }
            if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    static func filter(_ items: [WindowItem], query: String) -> [WindowItem] {
        WindowSearch.results(items, query: query).map(\.item)
    }

    static func nextIndex(_ current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + delta) % count + count) % count
    }
}

@MainActor @Observable
final class Preferences {
    var enabled = true { didSet { save() } }
    var includeMinimized = true { didSet { save() } }
    var includeHidden = true { didSet { save() } }
    var includeWindowless = true { didSet { save() } }
    var shortcuts = ShortcutConfiguration() { didSet { save() } }
    var sameAppShortcut = true { didSet { save() } }
    var compact = true { didSet { save() } }
    var excludedBundleIDs = "" { didSet { save() } }
    var rules: [ExclusionRule] = [] { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        includeMinimized = d.object(forKey: "includeMinimized") as? Bool ?? true
        includeHidden = d.object(forKey: "includeHidden") as? Bool ?? true
        includeWindowless = d.object(forKey: "includeWindowless") as? Bool ?? true
        if let data = d.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data), saved.isValid { shortcuts = saved }
        sameAppShortcut = d.object(forKey: "sameAppShortcut") as? Bool ?? true
        compact = d.object(forKey: "compact") as? Bool ?? true
        excludedBundleIDs = d.string(forKey: "excludedBundleIDs") ?? ""
        if let data = d.data(forKey: "rules"), let saved = try? JSONDecoder().decode([ExclusionRule].self, from: data) { rules = saved }
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        let d = defaults
        d.set(enabled, forKey: "enabled")
        d.set(includeMinimized, forKey: "includeMinimized")
        d.set(includeHidden, forKey: "includeHidden")
        d.set(includeWindowless, forKey: "includeWindowless")
        if let data = try? JSONEncoder().encode(shortcuts) { d.set(data, forKey: "shortcuts") }
        d.set(sameAppShortcut, forKey: "sameAppShortcut")
        d.set(compact, forKey: "compact")
        d.set(excludedBundleIDs, forKey: "excludedBundleIDs")
        if let data = try? JSONEncoder().encode(rules) { d.set(data, forKey: "rules") }
    }

    func accepts(_ item: WindowItem) -> Bool {
        let excluded = Set(excludedBundleIDs.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        return (includeMinimized || !item.minimized)
            && (includeHidden || !item.hidden)
            && (includeWindowless || !item.isAppOnly)
            && !excluded.contains(item.bundleID)
            && !rules.contains { $0.matches(item) }
    }
}
