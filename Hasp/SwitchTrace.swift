import OSLog
import Foundation

enum SwitchTrace {
    static let signposter = OSSignposter(subsystem: "app.hasp.menu", category: "SwitchPerformance")

    static func intent(_ kind: String) {
        signposter.emitEvent("SwitchIntent", "kind=\(kind, privacy: .public)")
    }

    static func applied(_ kind: String) {
        signposter.emitEvent("SwitchStateApplied", "kind=\(kind, privacy: .public)")
    }

    static func operation<T>(_ kind: String, _ body: () async -> T) async -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let state = signposter.beginInterval("SwitchBackend", id: signposter.makeSignpostID(), "kind=\(kind, privacy: .public)")
        let result = await body()
        signposter.endInterval("SwitchBackend", state)
        duration(kind, since: start)
        return result
    }

    static func duration(_ kind: String, since start: UInt64) {
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        signposter.emitEvent("SwitchDuration", "kind=\(kind, privacy: .public) ms=\(ms, privacy: .public)")
        // Opt-in diagnosis records no app names, device addresses or content.
        // File writes happen on a worker, never inside the UI click handler.
        guard let index = CommandLine.arguments.firstIndex(of: "--latency-log"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        let path = CommandLine.arguments[index + 1]
        latencyQueue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: ["kind": kind, "ms": ms, "at": Date().timeIntervalSince1970]),
                  let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])) } catch {}
        }
    }

    private static let latencyQueue = DispatchQueue(label: "app.hasp.latency-log", qos: .utility)
}
