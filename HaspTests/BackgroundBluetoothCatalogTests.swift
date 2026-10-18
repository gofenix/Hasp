import Foundation

@main
enum BackgroundBluetoothCatalogTests {
    static func main() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var calls = 0
        let catalog = BackgroundBluetoothCatalog {
            precondition(!Thread.isMainThread, "Profiler must run off the UI thread")
            lock.lock(); calls += 1; lock.unlock()
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
        lock.lock(); precondition(calls == 1); lock.unlock()
        release.signal()
        pump(until: { updated })
        precondition(catalog.values == ["001122334455": .trackpad])
        catalog.refresh { preconditionFailure("Fresh cache should be reused") }
        lock.lock(); precondition(calls == 1); lock.unlock()
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
