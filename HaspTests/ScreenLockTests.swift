import AppKit
import Foundation
import SwiftUI

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

@main enum ScreenLockTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "app.hasp.lock.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: SettingsStore(defaults: defaults))
        var calls = 0, shown = 0
        var dismissals: [() -> Void] = []
        model.screenLockAction = { calls += 1 }
        model.dismissPanel = { dismissals.append($0) }
        model.presentPanel = { shown += 1 }
        precondition(!model.screenLockState.pending && calls == 0)
        model.lockScreen()
        precondition(model.screenLockState.pending && calls == 0 && dismissals.count == 1,
                     "The panel must finish closing before the system action")
        model.lockScreen()
        precondition(dismissals.count == 1, "Repeated clicks while dismissing must coalesce")
        dismissals[0]()
        precondition(calls == 1 && !model.screenLockState.pending && model.screenLockState.message == nil)
        dismissals[0]()
        precondition(calls == 1, "A repeated completion must not lock twice")
        model.screenLockAction = { throw ScreenLockError.unavailable }
        model.lockScreen()
        precondition(model.screenLockState.pending)
        dismissals[1]()
        precondition(!model.screenLockState.pending && shown == 1 && model.screenLockState.message?.contains("⌃⌘Q") == true)
        model.screenLockAction = { calls += 1 }
        model.dismissPanel = nil
        model.lockScreen()
        precondition(calls == 2 && model.screenLockState.message == nil)

        // Render the actual complete panel with inert actions, without showing
        // any window or calling the native lock function.
        model.menuBarIcons = (0..<20).map { MenuBarIcon(id: "fake\($0)", name: "App \($0)") }
        model.menuBarFolded = true
        model.bluetoothGate = .ready
        model.outputs = [OutputItem(id: "fake-mac", name: "MacBook Pro 扬声器", kind: .mac, isCurrent: true, pending: false)]
        func render(dark: Bool, height: CGFloat, message: String? = nil) throws {
            model.screenLockState.message = message
            let host = NSHostingView(rootView: PanelView(maximumHeight: height).environmentObject(model)
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(dark ? Color(white: 0.12) : Color(white: 0.97)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            for _ in 0..<4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                host.layoutSubtreeIfNeeded()
                window.setContentSize(host.fittingSize)
            }
            precondition(!window.isVisible && host.fittingSize.height <= height + 1)
            func button(_ view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.accessibilityIdentifier() == "hasp.lock-screen" { return button }
                return view.subviews.lazy.compactMap(button).first
            }
            guard let control = button(host) else { fatalError("Missing lock button") }
            let bounds = control.convert(control.bounds, to: host)
            precondition(bounds.width >= 28 && bounds.height >= 28, "Keep an adequate hit area")
            let topDistance = host.isFlipped ? bounds.minY : host.bounds.maxY - bounds.maxY
            precondition(topDistance < 40, "Lock must stay in the fixed top region")
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Missing render") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if height == 540 && message == nil {
                try bitmap.representation(using: .png, properties: [:])!.write(to:
                    URL(fileURLWithPath: "../verification/lock-panel-\(dark ? "dark" : "light").png"))
                let crop = NSRect(x: 0, y: host.isFlipped ? 0 : host.bounds.maxY - 100, width: host.bounds.width, height: 100)
                let header = host.bitmapImageRepForCachingDisplay(in: crop)!
                host.cacheDisplay(in: crop, to: header)
                try header.representation(using: .png, properties: [:])!.write(to:
                    URL(fileURLWithPath: "../verification/lock-header-\(dark ? "dark" : "light").png"))
                if !dark {
                    control.performClick(nil) // Hidden fake-only UI action.
                    precondition(calls == 3, "The visible button must invoke the injected action exactly once")
                }
            }
        }
        try render(dark: false, height: 540)
        try render(dark: true, height: 540)
        try render(dark: true, height: 360)
        try render(dark: true, height: 360, message: "锁屏失败：当前系统的锁屏接口不可用，请使用 ⌃⌘Q 锁屏。")
        precondition(calls == 3 && shown == 1, "Only the explicit fake UI action may invoke the injected backend")
        print("PASS: dismiss-before-lock, single invocation, error/retry; fixed 28pt header, light/dark and 360/540pt panel bounds; no native lock invoked")
    }
}
