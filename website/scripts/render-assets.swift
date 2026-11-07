// Production UI, synthetic data, hidden windows. No live services are started.
import AppKit
import SwiftUI
@MainActor enum SettingsWindow { static func show(model: AppModel) {} }
@main enum WebsiteAssets {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "HaspWebsiteAssets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(services: SwitchServices(appearance: { _ in true }, audio: { _ in false },
            device: { _, _ in false }, snapshot: { _ in HardwareSnapshot(outputs: [], devices: [], batteries: [:]) }),
            store: SettingsStore(defaults: defaults))
        model.bluetoothGate = .ready
        model.outputs = [
            OutputItem(id: "mac", name: "MacBook Pro 扬声器", kind: .mac, isCurrent: true, pending: false),
            OutputItem(id: "airpods", name: "AirPods Pro", kind: .bluetooth, isCurrent: false, pending: false,
                battery: "86%", bluetoothAddress: "demo-headphones")]
        model.inputs = [
            DeviceItem(address: "demo-keyboard", name: "Magic Keyboard", kind: .keyboard, connected: true,
                pending: false, failed: false, battery: "92%"),
            DeviceItem(address: "demo-mouse", name: "Magic Mouse", kind: .mouse, connected: true,
                pending: false, failed: false, battery: "78%")]
        for variant in ["overview", "audio", "appearance", "fold"] {
            model.outputs[0].isCurrent = variant != "audio"
            model.outputs[1].isCurrent = variant == "audio"
            model.isDark = variant == "appearance"
            model.scheduleMode = variant == "appearance" ? .fixed : .off
            model.menuBarFolded = variant == "fold"
            model.menuBarIcons = variant == "fold" ? [
                MenuBarIcon(id: "demo-wifi", name: "Wi-Fi", status: "已连接", symbol: "wifi"),
                MenuBarIcon(id: "demo-sound", name: "声音", symbol: "speaker.wave.2"),
                MenuBarIcon(id: "demo-battery", name: "电池", status: "86%", symbol: "battery.100percent")] : []
            let dark = variant == "appearance"
            let root = PanelView(maximumHeight: 660, initiallyExpanded: true).environment(model)
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(dark ? Color(white: 0.13) : Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 13))
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 660),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            for _ in 0..<6 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                host.layoutSubtreeIfNeeded()
                window.setContentSize(host.fittingSize)
            }
            precondition(!window.isVisible)
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Empty render") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Empty PNG") }
            try data.write(to: directory.appendingPathComponent("panel-\(variant).png"))
            print("Rendered \(variant): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
    }
}
