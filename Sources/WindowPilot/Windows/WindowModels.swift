import AppKit

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
