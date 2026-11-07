import AppKit
import SwiftUI
import Foundation

@MainActor enum SettingsWindow {
    static var shows = 0
    static func show(model: AppModel) { shows += 1 }
}

private actor AppearanceProbe {
    var success = true
    func set(_ intent: AppearanceIntent) -> Bool { let ok = success; success = true; return ok }
    func failNext() { success = false }
}

@main enum ApprovedDesignTests {
    @MainActor static func settle(_ model: AppModel) async {
        let deadline = Date().addingTimeInterval(3)
        while model.appearanceState.requested != nil {
            precondition(Date() < deadline)
            try! await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "HaspApprovedDesign.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.automaticSchedule = .fixed
        let probe = AppearanceProbe()
        let model = AppModel(services: SwitchServices(appearance: { await probe.set($0) }, audio: { _ in false },
            device: { _,_ in false }, snapshot: { _ in HardwareSnapshot(outputs: [], devices: [], batteries: [:]) }), store: store)
        model.selectAppearance(.dark)
        await settle(model)
        precondition(model.appearanceChoice == .dark && model.isDark && model.scheduleMode == .off)
        model.selectAppearance(.automatic)
        precondition(model.appearanceChoice == .automatic && model.scheduleMode == .fixed)
        await settle(model)
        model.selectAppearance(.light)
        await settle(model)
        precondition(!model.isDark && model.scheduleMode == .off && model.appearanceChoice == .light)
        await probe.failNext()
        model.selectAppearance(.dark)
        await settle(model)
        precondition(!model.isDark && model.appearanceChoice == .light && model.permissionMessage != nil)
        model.selectSchedule(.custom)
        precondition(SettingsWindow.shows == 0, "Changing a schedule must not unexpectedly open a window")
        model.openSettings()
        precondition(SettingsWindow.shows == 1 && model.scheduleMode == .custom, "Opening settings must not change the chosen mode")
        await settle(model)
        model.scheduleMode = .off
        model.permissionMessage = nil

        model.bluetoothGate = .ready
        model.outputs = [
            OutputItem(id: "open", name: "OpenDots ONE by Shokz", kind: .bluetooth, isCurrent: true, pending: false, bluetoothAddress: "test-open"),
            OutputItem(id: "mac", name: "MacBook Pro 扬声器", kind: .mac, isCurrent: false, pending: false),
            OutputItem(id: "wired", name: "外置耳机", kind: .wired, isCurrent: false, pending: false),
            OutputItem(id: "airpods", name: "AirPods Pro", kind: .bluetooth, isCurrent: false, pending: false, bluetoothAddress: "test-airpods", connected: false),
            OutputItem(id: "airpods2", name: "AirPods Pro #2", kind: .bluetooth, isCurrent: false, pending: false, bluetoothAddress: "test-airpods2", connected: false),
            OutputItem(id: "spare", name: "备用耳机", kind: .bluetooth, isCurrent: false, pending: false, bluetoothAddress: "test-spare", connected: false)
        ]
        model.inputs = [
            DeviceItem(address: "keyboard", name: "键盘", kind: .keyboard, connected: true, pending: false, failed: false, battery: "88%"),
            DeviceItem(address: "mouse", name: "MX Anywhere 3S", kind: .mouse, connected: true, pending: false, failed: false, battery: "60%"),
            DeviceItem(address: "trackpad", name: "Magic Trackpad", kind: .trackpad, connected: true, pending: false, failed: false, battery: "65%"),
            DeviceItem(address: "ipad", name: "iPad", kind: .other, connected: false, pending: false, failed: false),
            DeviceItem(address: "computer", name: "MacBook Pro", kind: .other, connected: false, pending: false, failed: false)
        ]
        // Check the actual production row across native operation states.
        var item = model.outputs[3]
        var rowHeights: [CGFloat] = []
        for operation: AudioRowOperation? in [nil, .connecting, .waitingForOutput, .switching, .disconnecting] {
            item.operation = operation; item.pending = operation != nil
            let view = NSHostingView(rootView: SoundOutputRow(item: item, onUse: {}, onDisconnect: {}))
            view.frame.size.width = 300
            view.layoutSubtreeIfNeeded()
            rowHeights.append(view.fittingSize.height)
        }
        precondition(rowHeights.allSatisfy { abs($0 - 44) < 1 }, "Connecting must not push the next row down: \(rowHeights)")

        // Native segmentation must still dispatch all three choices after resizing.
        var selected = AppearanceChoice.light
        let selector = NSHostingView(rootView: AppearanceSelector(selection: Binding(
            get: { selected }, set: { selected = $0 })))
        selector.frame.size = NSSize(width: 288, height: 24)
        selector.layoutSubtreeIfNeeded()
        func segmentedControl(in view: NSView) -> NSSegmentedControl? {
            if let control = view as? NSSegmentedControl { return control }
            return view.subviews.lazy.compactMap { segmentedControl(in: $0) }.first
        }
        let control = segmentedControl(in: selector)!
        for (index, choice) in AppearanceChoice.allCases.enumerated() {
            control.selectedSegment = index
            precondition(control.sendAction(control.action, to: control.target))
            precondition(selected == choice)
        }

        var longDevice = model.inputs[0]
        longDevice.name = "工作室的超长名称无线键盘 Keyboard with a very long name"
        for battery: String? in [nil, "0%", "8%", "100%"] {
            longDevice.battery = battery
            let row = NSHostingView(rootView: DeviceRow(item: longDevice, onToggle: { _ in }))
            row.frame.size.width = 288
            row.layoutSubtreeIfNeeded()
            precondition(abs(row.fittingSize.height - 36) < 1, "Long names or battery values must not change device row pitch")
        }

        var sizes: [String: Double] = [:]
        for dark in [false, true] {
            model.isDark = dark
            for expanded in [false, true] {
                let name = "\(dark ? "dark" : "light")-\(expanded ? "expanded" : "collapsed")"
                let height = render(model, expanded: expanded, dark: dark, limit: 1100, filename: name)
                sizes[name] = height
            }
        }
        precondition(sizes["light-expanded"]! > sizes["light-collapsed"]! + 100)
        model.menuBarFolded = true // Presentation only; no native folding services.
        model.menuBarIcons = (0..<30).map { MenuBarIcon(id: "test-\($0)", name: "应用 \($0)") }
        let bounded = render(model, expanded: true, dark: false, limit: 560, filename: "small-screen")
        precondition(bounded <= 560, "Full expansion must fit the supplied screen limit")

        model.menuBarFolded = false
        model.scheduleMode = .solar
        _ = render(model, expanded: false, dark: false, limit: 1100, filename: "automatic-schedule")
        model.scheduleMode = .off
        model.outputs[0].name = "工作室的超长耳机名称 Headphones with a very long name"
        model.outputs[0].pending = true
        model.outputs[0].operation = .disconnecting
        model.inputs[0] = longDevice
        model.inputs[0].pending = true
        model.permissionMessage = "无法切换外观，请在系统设置中允许 Hasp 控制 System Events 后重试。"
        _ = render(model, expanded: true, dark: false, limit: 1100, filename: "loading-long-names")
        model.outputs[0].pending = false
        model.outputs[0].operation = nil
        model.outputs[0].failed = true
        model.outputs[0].failure = .disconnection
        model.outputs[3].failed = true
        model.outputs[3].failure = .connection
        model.inputs[0].pending = false
        model.inputs[0].failed = true
        _ = render(model, expanded: true, dark: true, limit: 1100, filename: "errors-long-names")
        model.bluetoothGate = .denied
        _ = render(model, expanded: false, dark: false, limit: 1100, filename: "permission-denied")
        model.outputs = []
        model.inputs = []
        model.bluetoothGate = .ready
        _ = render(model, expanded: false, dark: false, limit: 240, filename: "empty-240pt")
        print("Panel checks passed: appearance modes, failure rollback, native segment actions, settings without mode changes; fixed 44pt audio and 36pt device rows; expanded/collapsed light and dark renders; loading, retry, permissions, long names, empty state; 240pt and 560pt screen bounds. Heights: \(sizes)")
    }

    @MainActor static func render(_ model: AppModel, expanded: Bool, dark: Bool, limit: CGFloat, filename: String) -> CGFloat {
        let host = NSHostingView(rootView: PanelView(maximumHeight: limit, initiallyExpanded: expanded).environment(model)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(dark ? Color(white: 0.13) : Color(white: 0.96)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            host.layoutSubtreeIfNeeded()
            window.setContentSize(host.fittingSize)
        }
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "verification/approved-\(filename).png"))
        }
        precondition(!window.isVisible, "Never show test windows on the user's desktop")
        precondition(abs(host.fittingSize.width - 320) < 1, "Long content must not widen the panel")
        precondition(host.fittingSize.height <= limit, "The footer must stay within the available height")
        return host.fittingSize.height
    }
}
