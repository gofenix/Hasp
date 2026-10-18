import AppKit
import Combine
import SwiftUI

#if !PERMISSION_FOCUSED_TESTS
@MainActor enum SettingsWindow { static func show(model: AppModel) {} }
#endif

@MainActor final class PermissionGate: PermissionBackend {
    var result = Dictionary(uniqueKeysWithValues: HaspPermission.allCases.map { ($0, PermissionStatus.denied) })
    var requests: [HaspPermission] = []
    var openings: [HaspPermission] = []
    var reads = 0
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    var canOpen = true
    var requestError: String?
    var changed: (@MainActor () -> Void)?
    var activeChecks = 0
    var maximumConcurrentChecks = 0
    func check() async -> [HaspPermission: PermissionStatus] {
        reads += 1
        activeChecks += 1
        maximumConcurrentChecks = max(maximumConcurrentChecks, activeChecks)
        let snapshot = result
        if hold { await withCheckedContinuation { continuation = $0 } }
        activeChecks -= 1
        return snapshot
    }
    func request(_ permission: HaspPermission) async -> String? { requests.append(permission); return requestError }
    func openSettings(_ permission: HaspPermission) -> Bool { openings.append(permission); return canOpen }
    func observeChanges(_ handler: @escaping @MainActor () -> Void) { changed = handler }
}

@main enum PermissionTests {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() {
            precondition(Date() < deadline, "Permission test timed out")
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let backend = PermissionGate()
        let center = PermissionCenter(backend: backend)
        precondition(center.status(.accessibility) == .checking)
        await center.refresh()
        var quietSignals = 0
        let observation = center.objectWillChange.sink { quietSignals += 1 }
        for _ in 0..<12 { await center.refresh() }
        precondition(quietSignals == 0, "Unchanged passive checks must cause zero redraw signals")
        backend.hold = true
        let reads = backend.reads
        let first = Task { await center.refresh(manual: true) }
        while backend.continuation == nil { await Task.yield() }
        let join = Task { await center.refresh() }
        let action = Task { await center.performAction(.accessibility) }
        try await wait { backend.openings == [.accessibility] }
        precondition(center.refreshing && center.pending.contains(.accessibility), "The action must reach the system before the slow check finishes")
        let secondAction = Task { await center.performAction(.menuConfiguration) }
        try await wait { backend.openings.count == 2 }
        precondition(backend.reads == reads + 1 && backend.maximumConcurrentChecks == 1, "Checks coalesce without swallowing clicks")
        backend.result[.accessibility] = .authorized
        backend.result[.menuConfiguration] = .readable
        backend.hold = false; backend.continuation?.resume(); await first.value
        await join.value; await action.value; await secondAction.value
        precondition(backend.maximumConcurrentChecks == 1 && center.pending.isEmpty && !center.refreshing)
        precondition(center.status(.accessibility) == .authorized && center.status(.menuConfiguration) == .readable,
                     "A stale pre-request snapshot must not overwrite post-action authorization")
        backend.result[.accessibility] = .denied
        backend.result[.menuConfiguration] = .denied
        backend.openings = []
        await center.refresh()
        await center.performAction(.accessibility)
        precondition(backend.openings == [.accessibility] && backend.requests.isEmpty)
        precondition(center.status(.accessibility) == .denied, "Opening settings never implies consent")
        backend.result[.bluetooth] = .notRequested
        backend.result[.automation] = .unknown
        await center.refresh()
        await center.performAction(.bluetooth)
        await center.performAction(.automation)
        precondition(backend.requests == [.bluetooth, .automation])
        backend.result[.bluetooth] = .authorized
        backend.result[.location] = .restricted
        backend.result[.menuConfiguration] = .readable
        await center.refresh()
        await center.performAction(.bluetooth)
        await center.performAction(.menuConfiguration)
        precondition(backend.requests.count == 2 && backend.openings.count == 1)
        await center.performAction(.location)
        precondition(backend.openings.last == .location, "Restricted access uses Settings, no repeat prompt")
        backend.canOpen = false
        await center.performAction(.accessibility)
        precondition(center.message != nil && center.requesting == nil && !center.refreshing)
        precondition(NativePermissionBackend.automationStatus(0) == .authorized)
        precondition(NativePermissionBackend.automationStatus(-1744) == .notRequested)
        precondition(NativePermissionBackend.automationStatus(-1743) == .denied)
        precondition(NativePermissionBackend.automationStatus(-600) == .unknown)
        precondition(NativePermissionBackend.automationRequestError(0) == nil)
        precondition(NativePermissionBackend.automationRequestError(-1743) != nil)
        precondition(NativePermissionBackend.automationRequestError(-600)?.contains("-600") == true)
        backend.requestError = "系统拒绝了请求"
        await center.performAction(.automation)
        precondition(center.feedback[.automation] == "系统拒绝了请求", "Native failures must be visible")
        backend.continuation = nil; backend.hold = true
        let preCallbackRead = Task { await center.refresh() }
        try await wait { backend.continuation != nil }
        backend.result[.location] = .authorized
        backend.changed?()
        backend.hold = false; backend.continuation?.resume()
        await preCallbackRead.value
        try await wait { center.status(.location) == .authorized }
        precondition(center.feedback[.location] == nil, "Authorization callbacks refresh without polling and clear stale guidance")
        precondition(backend.maximumConcurrentChecks == 1)
        for permission in HaspPermission.allCases {
            precondition(permission.settingsURL.absoluteString.contains(permission.settingsAnchor))
        }
        var settingsAttempts: [URL] = []
        let fallbackOpened = NativePermissionBackend.openSettingsLink(.menuConfiguration, opener: {
            settingsAttempts.append($0); return settingsAttempts.count == 2
        })
        precondition(fallbackOpened && settingsAttempts.count == 2)
        precondition(settingsAttempts[0].absoluteString.contains("com.apple.settings.PrivacySecurity.extension"))
        precondition(settingsAttempts[1].absoluteString.contains("com.apple.preference.security"))
        precondition(settingsAttempts.allSatisfy { $0.absoluteString.contains("Privacy_AllFiles") })
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = folder.appendingPathComponent("missing.plist")
        precondition(NativePermissionBackend.configurationAccess(at: missing) == .unknown, "Missing file is not permission denial")
        let valid = folder.appendingPathComponent("probe.plist")
        try PropertyListSerialization.data(fromPropertyList: ["test": true], format: .binary, options: 0).write(to: valid)
        precondition(NativePermissionBackend.configurationAccess(at: valid) == .readable)
        try Data("invalid".utf8).write(to: valid)
        precondition(NativePermissionBackend.configurationAccess(at: valid) == .unknown)
        backend.result[.accessibility] = .authorized
        backend.result[.automation] = .denied
        backend.result[.location] = .notRequested
        backend.result[.menuConfiguration] = .denied
        await center.refresh()
        let requestCount = backend.requests.count, openCount = backend.openings.count
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: PermissionSettingsView(center: center))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 610), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 610)
            host.layoutSubtreeIfNeeded()
            precondition(!window.isVisible, "Preview must never take the user's screen")
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("permissions-\(name).png"))
        }
        precondition(backend.requests.count == requestCount && backend.openings.count == openCount, "Rendering cannot prompt or open settings")
        observation.cancel()
        print("PASS: 12 unchanged passive checks publish 0 signals; clicks during blocked checks reach the backend; reads coalesce; stale checks cannot undo consent; native errors/callbacks; invisible light/dark previews")
    }
}
