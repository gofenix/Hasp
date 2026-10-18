import AppKit
import SwiftUI

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

@MainActor final class PermissionDesignBackend: PermissionBackend {
    var result = Dictionary(uniqueKeysWithValues: HaspPermission.allCases.map { ($0, PermissionStatus.authorized) })
    var checks = 0
    var requests: [HaspPermission] = []
    var openings: [HaspPermission] = []
    var requestMessage: String?
    var heldRequest: CheckedContinuation<Void, Never>?
    var holdRequest = false
    func check() async -> [HaspPermission: PermissionStatus] { checks += 1; return result }
    func request(_ permission: HaspPermission) async -> String? {
        requests.append(permission)
        if holdRequest { await withCheckedContinuation { heldRequest = $0 } }
        if requestMessage == nil { result[permission] = .authorized }
        return requestMessage
    }
    func openSettings(_ permission: HaspPermission) -> Bool { openings.append(permission); return true }
}

private struct PermissionFixture: View {
    @ObservedObject var navigation: SettingsState
    let center: PermissionCenter
    var expanded = false
    var body: some View {
        SettingsLayout(selection: Binding(get: { navigation.selectedTab }, set: { navigation.selectedTab = $0 })) {
            if navigation.selectedTab == .permissions {
                PermissionSettingsView(center: center, initiallyExpanded: expanded,
                                       bundleURL: URL(fileURLWithPath: "/Applications/Hasp.app"))
            } else { Text("通用设置").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}

@main enum PermissionDesignTests {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() {
            precondition(Date() < deadline, "UI action did not reach the fixture backend")
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    @MainActor static func settle(_ window: NSWindow) {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
    @MainActor static func render<Content: View>(_ content: Content, size: NSSize, dark: Bool, file: URL) -> (NSWindow, NSHostingView<some View>) {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(size)
        settle(window)
        precondition(!window.isVisible, "UI checks must never take the user's screen")
        precondition(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: file)
        return (window, host)
    }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backend = PermissionDesignBackend()
        backend.result[.menuConfiguration] = .readable
        let center = PermissionCenter(backend: backend)
        await center.refresh()
        let state = SettingsState(); state.selectedTab = .permissions
        let clipboard = NSPasteboard.general.changeCount
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            _ = render(PermissionFixture(navigation: state, center: center), size: NSSize(width: 560, height: 540), dark: dark,
                       file: folder.appendingPathComponent("authorized-\(name).png"))
            _ = render(PermissionFixture(navigation: state, center: center, expanded: true), size: NSSize(width: 560, height: 700), dark: dark,
                       file: folder.appendingPathComponent("help-\(name).png"))
        }
        precondition(backend.requests.isEmpty && backend.openings.isEmpty && clipboard == NSPasteboard.general.changeCount)

        backend.result[.automation] = .denied
        backend.result[.bluetooth] = .notRequested
        backend.result[.location] = .restricted
        backend.result[.menuConfiguration] = .unknown
        await center.refresh()
        _ = render(PermissionFixture(navigation: state, center: center), size: NSSize(width: 560, height: 540), dark: false,
                                   file: folder.appendingPathComponent("mixed-light.png"))
        let reads = backend.checks
        await center.refresh(manual: true)
        precondition(backend.checks > reads)
        backend.holdRequest = true
        let request = Task { await center.performAction(.bluetooth) }
        try await wait { backend.requests == [.bluetooth] && backend.heldRequest != nil }
        precondition(center.pending.contains(.bluetooth))
        _ = render(PermissionFixture(navigation: state, center: center), size: NSSize(width: 560, height: 540), dark: true,
                   file: folder.appendingPathComponent("pending-dark.png"))
        backend.holdRequest = false; backend.heldRequest?.resume()
        await request.value
        try await wait { center.status(.bluetooth).granted && !center.pending.contains(.bluetooth) }
        precondition(backend.openings.isEmpty && clipboard == NSPasteboard.general.changeCount)

        backend.result[.automation] = .unknown
        backend.requestMessage = String(repeating: "系统拒绝了这次请求，请检查 System Events 的授权设置。", count: 3)
        await center.refresh()
        await center.performAction(.automation)
        for size in [NSSize(width: 520, height: 540), NSSize(width: 560, height: 460), NSSize(width: 520, height: 460)] {
            _ = render(PermissionFixture(navigation: state, center: center, expanded: true), size: size, dark: false,
                                  file: folder.appendingPathComponent("long-error-\(Int(size.width))x\(Int(size.height)).png"))
        }
        precondition(backend.requests == [.bluetooth, .automation] && backend.openings.isEmpty)
        let suite = "HaspGeneralDesign.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(services: SwitchServices(appearance: { _ in false }, audio: { _ in false }, device: { _, _ in false },
            snapshot: { _ in HardwareSnapshot(outputs: [], devices: [], batteries: [:]) }), store: SettingsStore(defaults: defaults))
        for dark in [false, true] {
            _ = render(SettingsView().environmentObject(model), size: NSSize(width: 560, height: 540), dark: dark,
                       file: folder.appendingPathComponent("general-\(dark ? "dark" : "light").png"))
        }
        precondition(clipboard == NSPasteboard.general.changeCount)
        print("PASS: invisible native permission renders in light/dark, all authorized/mixed/pending/long-error/help states; general settings; 520pt minimum width and 460pt minimum height; refresh and authorization fixtures; no native requests, window activation, mouse, keyboard, or clipboard changes")
    }
}
