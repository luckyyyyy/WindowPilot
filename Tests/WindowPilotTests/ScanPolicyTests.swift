import Testing
@testable import WindowPilot

struct ScanPolicyTests {
    private func app(_ bundleID: String = "com.apple.WebKit.WebContent", regular: Bool = false) -> AppRecord {
        AppRecord(pid: 12345, name: "Test", bundleID: bundleID, hidden: false, regular: regular)
    }

    @Test func avoidsWindowlessRenderWorkersWithoutHidingRealWindows() {
        let worker = app()
        #expect(!ScanPolicy.shouldQuery(app: worker, hasServerWindow: false, hasCachedWindow: false))
        #expect(ScanPolicy.shouldQuery(app: worker, hasServerWindow: true, hasCachedWindow: false))
        // A minimized window may no longer appear in WindowServer metadata.
        #expect(ScanPolicy.shouldQuery(app: worker, hasServerWindow: false, hasCachedWindow: true))
        #expect(ScanPolicy.shouldQuery(app: app(regular: true), hasServerWindow: false, hasCachedWindow: false))
    }

    @Test func keepsAccessorySettingsAppsAndOtherUIHostingServices() {
        for bundleID in ["test.menubar-settings", "com.apple.SystemSettings", "test.dialog.xpc", "org.browser.app"] {
            #expect(ScanPolicy.shouldQuery(app: app(bundleID), hasServerWindow: false, hasCachedWindow: false))
        }
    }

    @Test func timeoutRetryBacksOffWithABoundedDelay() {
        var policy = ScanRetryPolicy()
        let target = app("test.slow-app", regular: true)
        var now = 100.0
        for delay in [1.0, 2, 4, 8, 15, 15] {
            policy.failed(app: target, now: now)
            #expect(!policy.shouldAttempt(app: target, now: now + delay - 0.01, frontPID: nil))
            #expect(policy.shouldAttempt(app: target, now: now + delay, frontPID: nil))
            now += delay
        }
    }

    @Test func activationAndWindowNotificationsBypassBackoff() {
        var policy = ScanRetryPolicy()
        let target = app()
        policy.failed(app: target, now: 100)
        #expect(policy.shouldAttempt(app: target, now: 100, frontPID: target.pid))
        policy.reset(pid: target.pid)
        #expect(policy.shouldAttempt(app: target, now: 100, frontPID: nil))
    }

    @Test func processExitAndPIDReuseDoNotInheritAnotherAppsBackoff() {
        var policy = ScanRetryPolicy()
        policy.failed(app: app(), now: 100)
        #expect(policy.shouldAttempt(app: app("test.another-app"), now: 100, frontPID: nil))
        policy.retain(pids: [])
        #expect(policy.shouldAttempt(app: app(), now: 100, frontPID: nil))
    }
    @Test func notificationBurstsMergeAppsWithoutDowngradingFullReconciliation() {
        #expect(ScanScope.apps([1]).merging(.apps([2, 3])) == .apps([1, 2, 3]))
        #expect(ScanScope.all.merging(.apps([2])) == .all)
        #expect(ScanScope.apps([2]).merging(.all) == .all)
        #expect(ScanScope.all.pids == nil)
        #expect(ScanScope.apps([1, 2]).pids == [1, 2])
    }

}
