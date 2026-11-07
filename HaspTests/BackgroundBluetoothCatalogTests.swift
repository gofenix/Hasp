import Foundation
import Synchronization

@main
enum BackgroundBluetoothCatalogTests {
    static func main() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let calls = Mutex(0)
        let catalog = BackgroundBluetoothCatalog {
            precondition(!Thread.isMainThread, "Profiler must run off the UI thread")
            calls.withLock { $0 += 1 }
            started.signal()
            precondition(release.wait(timeout: .now() + 5) == .success)
            return ["001122334455": .trackpad]
        }
        var updated = false
        catalog.refresh {
            precondition(Thread.isMainThread)
            updated = true
        }
        precondition(started.wait(timeout: .now() + 3) == .success)
        // A hung profiler must neither stall UI reads nor queue more profilers.
        for _ in 0..<100 {
            precondition(catalog.values.isEmpty)
            catalog.refresh { preconditionFailure("Duplicate refresh") }
        }
        var heartbeat = false
        DispatchQueue.main.async { heartbeat = true }
        pump(until: { heartbeat })
        precondition(!updated)
        precondition(calls.withLock { $0 == 1 })
        release.signal()
        pump(until: { updated })
        precondition(catalog.values == ["001122334455": .trackpad])
        catalog.refresh { preconditionFailure("Fresh cache should be reused") }
        precondition(calls.withLock { $0 == 1 })
        print("ok: UI responsive during blocked refresh; requests coalesced; result delivered on main")
    }

    private static func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(condition(), "Main queue callback did not arrive")
    }
}
