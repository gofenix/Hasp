import Foundation

@main
enum PreferenceStoreTests {
    static func main() {
        let store = PreferenceStore(domain: "app.hasp.tests.\(UUID().uuidString)")
        defer {
            store.apply([:], removing: ["sound", "keep"], currentHost: true)
            store.apply([:], removing: ["sound", "keep"], currentHost: false)
        }
        store.apply(["sound": 18, "keep": 42])
        store.apply(["sound": 8])
        expect(store.integer("sound") == 8, "batch updates the intended current-host key")
        expect(store.integer("keep") == 42, "batch preserves unrelated preferences")
        store.apply(["sound": 99], currentHost: false)
        expect(store.integer("sound") == 8, "any-host writes must not overwrite current-host values")
        expect(store.integer("sound", currentHost: false) == 99, "any-host domain is addressed correctly")
        store.apply([:], removing: ["sound"])
        expect(store.integer("sound") == nil, "removal restores an absent current-host key")

        let controlCenter = PreferenceStore(domain: "com.apple.controlcenter")
        let keys = ["WiFi", "Battery", "Sound", "FocusModes", "Bluetooth", "AirDrop", "ScreenMirroring", "Display", "NowPlaying"]
        var times: [Double] = []
        for _ in 0..<3 {
            let start = ProcessInfo.processInfo.systemUptime
            controlCenter.refresh()
            for key in keys { _ = controlCenter.integer(key) }
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        print("Preference batch tests passed. Nine read-only CF preference lookups (ms): \(times)")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
