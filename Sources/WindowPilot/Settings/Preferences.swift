import Foundation
import Observation

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

@MainActor @Observable
final class Preferences {
    var enabled = true { didSet { save() } }
    var includeMinimized = true { didSet { save() } }
    var includeHidden = true { didSet { save() } }
    var includeWindowless = true { didSet { save() } }
    var shortcuts = ShortcutConfiguration() { didSet { save() } }
    var sameAppShortcut = true { didSet { save() } }
    var compact = true { didSet { save() } }
    var appearance = AppearancePreference.system { didSet { save() } }
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
        appearance = d.string(forKey: "appearance").flatMap(AppearancePreference.init(rawValue:)) ?? .system
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
        d.set(appearance.rawValue, forKey: "appearance")
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
