import Foundation

enum SystemBluetoothCatalog {
    private static let cache = BackgroundBluetoothCatalog(loader: load)

    static func kindsByAddress() -> [String: DeviceKind] {
        cache.values
    }

    static func refresh(onUpdate: @escaping @MainActor @Sendable () -> Void) {
        cache.refresh(onUpdate: onUpdate)
    }

    static func finishRefresh() async { await cache.finishRefresh() }

    static func normalize(_ address: String) -> String {
        address.lowercased().filter { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private static func load() -> [String: DeviceKind] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        // Drain first: a large JSON report must not fill the pipe while the
        // parent waits for the child to exit. This runs only on the worker.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var result: [String: DeviceKind] = [:]
        walk(json, into: &result)
        return result
    }

    private static func walk(_ value: Any, into result: inout [String: DeviceKind]) {
        if let dict = value as? [String: Any] {
            if let address = dict["device_address"] as? String,
               let minor = dict["device_minorType"] as? String,
               let kind = DeviceClassifier.classify(systemMinorType: minor) {
                result[normalize(address)] = kind
            }
            for child in dict.values {
                walk(child, into: &result)
            }
        } else if let list = value as? [Any] {
            for child in list {
                walk(child, into: &result)
            }
        }
    }
}

/// UI reads never wait for system_profiler, even when the cache has expired.
/// A single worker refreshes the snapshot and reports changes on the main queue.
final class BackgroundBluetoothCatalog: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.hasp.bluetooth-catalog", qos: .utility)
    private let loader: @Sendable () -> [String: DeviceKind]
    private let lifetime: TimeInterval
    private var snapshot: [String: DeviceKind] = [:]
    private var updatedAt = Date.distantPast
    private var loading = false

    init(lifetime: TimeInterval = 5, loader: @escaping @Sendable () -> [String: DeviceKind]) {
        self.lifetime = lifetime
        self.loader = loader
    }

    var values: [String: DeviceKind] {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func finishRefresh() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    func refresh(onUpdate: @escaping @MainActor @Sendable () -> Void) {
        lock.lock()
        guard !loading, Date().timeIntervalSince(updatedAt) >= lifetime else {
            lock.unlock()
            return
        }
        loading = true
        lock.unlock()
        queue.async { [self] in
            let result = loader()
            lock.lock()
            let changed = result != snapshot
            snapshot = result
            updatedAt = Date()
            loading = false
            lock.unlock()
            if changed { DispatchQueue.main.async(execute: onUpdate) }
        }
    }
}
