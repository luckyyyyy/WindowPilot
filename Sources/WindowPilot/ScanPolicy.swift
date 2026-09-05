import Foundation

/// These are render/network workers, not the owning browser application's UI.
/// An actual WindowServer window or an existing AX window overrides the exclusion.
enum ScanPolicy {
    private static let infrastructure: Set<String> = [
        "com.apple.WebKit.WebContent", "com.apple.WebKit.Networking", "com.apple.WebKit.GPU"
    ]

    static func shouldQuery(app: AppRecord, hasServerWindow: Bool, hasCachedWindow: Bool) -> Bool {
        app.regular || hasServerWindow || hasCachedWindow || !infrastructure.contains(app.bundleID)
    }
}

struct ScanRetryPolicy {
    private struct Failure {
        var count: Int
        var retryAfter: TimeInterval
        var bundleID: String
    }
    private var failures: [pid_t: Failure] = [:]

    mutating func retain(pids: Set<pid_t>) { failures = failures.filter { pids.contains($0.key) } }
    mutating func reset(pid: pid_t) { failures.removeValue(forKey: pid) }

    func shouldAttempt(app: AppRecord, now: TimeInterval, frontPID: pid_t?) -> Bool {
        guard app.pid != frontPID, let failure = failures[app.pid], failure.bundleID == app.bundleID else { return true }
        return now >= failure.retryAfter
    }

    mutating func failed(app: AppRecord, now: TimeInterval) {
        let old = failures[app.pid]
        let count = old?.bundleID == app.bundleID ? min((old?.count ?? 0) + 1, 5) : 1
        failures[app.pid] = Failure(count: count, retryAfter: now + min(pow(2, Double(count - 1)), 15), bundleID: app.bundleID)
    }
}

/// Merge bursts without losing a full reconciliation or another app's update.
enum ScanScope: Equatable {
    case all
    case apps(Set<pid_t>)

    var pids: Set<pid_t>? {
        if case .apps(let pids) = self { return pids }
        return nil
    }

    func merging(_ other: Self) -> Self {
        switch (self, other) {
        case (.apps(let lhs), .apps(let rhs)): .apps(lhs.union(rhs))
        default: .all
        }
    }
}
