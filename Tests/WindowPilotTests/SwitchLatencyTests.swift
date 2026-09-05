import AppKit
import Synchronization
import Testing
@testable import WindowPilot

struct SwitchLatencyTests {
    @Test @MainActor func windowActionsCompleteWhileTheScannerIsBlocked() async {
        let scanner = DispatchQueue(label: "test.blocked-scanner")
        let gate = DispatchSemaphore(value: 0)
        let scanFinished = Mutex(false)
        let scanUnblocked = Mutex(false)
        // Hold the real scan lane until all interactive operations have answered.
        // A generous deadlock deadline tolerates other AppKit tests occupying MainActor.
        // This checks queue independence, not a wall-clock latency benchmark.
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
            scanner.async {
                entered.resume()
                _ = gate.wait(timeout: .now() + 15)
                scanUnblocked.withLock { $0 = true }
            }
        }
        defer { gate.signal() }
        let catalog = WindowCatalog(scanQueue: scanner)
        catalog.scan(apps: [], frontPID: nil) { _ in scanFinished.withLock { $0 = true } }
        let item = WindowItem(id: "missing-test-window", pid: Int32.max, appName: "Fixture",
                              bundleID: "test.fixture", title: "Fixture", minimized: false, hidden: false,
                              isAppOnly: false, focused: false, lastUsed: 0)
        let restored = await withCheckedContinuation { continuation in
            catalog.restore(item) { continuation.resume(returning: $0) }
        }
        let raised = await withCheckedContinuation { continuation in
            catalog.raise(item) { continuation.resume(returning: $0) }
        }
        let closed = await withCheckedContinuation { continuation in
            catalog.close(item) { continuation.resume(returning: $0) }
        }
        let open = await withCheckedContinuation { continuation in
            catalog.isOpen(item) { continuation.resume(returning: $0) }
        }
        #expect(!restored && !raised && !closed && open == false)
        #expect(!scanUnblocked.withLock { $0 }, "Interactive actions waited for the blocked scan lane")
        #expect(!scanFinished.withLock { $0 }, "Interactive actions waited behind the scanner")
    }
}
