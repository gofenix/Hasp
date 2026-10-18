import AppKit
import Foundation
import SwiftUI

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

@main enum MenuBarFoldSwitchTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "app.hasp.fold-feedback.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let icons = (0..<16).map { MenuBarIcon(id: "fake\($0)", name: "Fake app \($0)", status: "Cached status") }
        let model = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { icons }, transition: { _, done in done() }, isTrusted: { true },
            requestAccess: { preconditionFailure("No real permissions") }, waitsForLayout: true,
            refreshesAfterTransition: false))
        model.menuBarIcons = icons
        var completions: [(MenuBarLayoutFailure?) -> Void] = []
        model.applyMenuBarLayout = { _, done in completions.append(done) }
        let host = NSHostingView(rootView: PanelView(maximumHeight: 540).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 540),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func render() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            host.layoutSubtreeIfNeeded()
            precondition(!window.isVisible, "Never show a window or operate the real Hasp instance")
        }
        func nativeSwitch(_ view: NSView) -> NSSwitch? {
            if let control = view as? NSSwitch { return control }
            return view.subviews.lazy.compactMap(nativeSwitch).first
        }
        render()
        guard let control = nativeSwitch(host) else {
            func names(_ view: NSView) -> [String] { [String(describing: type(of: view))] + view.subviews.flatMap(names) }
            fatalError("Missing native switch: \(names(host))")
        }
        precondition(control.state == .off && control.isEnabled)
        // Local action on an invisible fake-only control: no global event,
        // native preferences, app activation or real menu-bar operation.
        let start = DispatchTime.now().uptimeNanoseconds
        control.performClick(nil)
        render()
        let feedbackMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        precondition(completions.count == 1 && model.menuState.layoutPending)
        precondition(control.state == .on, "Requested ON must render while native completion is still blocked")
        precondition(!control.isEnabled && model.menuState.progressDescription == "正在折叠状态栏…")
        completions[0]("模拟失败")
        render()
        precondition(control.state == .off && control.isEnabled && model.menuBarMessage == "模拟失败")
        control.performClick(nil)
        render()
        precondition(control.state == .on && model.menuState.layoutPending)
        completions[1](nil)
        render()
        precondition(control.state == .on && control.isEnabled)
        model.menuBarRevealed = true
        render()
        precondition(control.state == .off, "Temporary native-menu reveal must still show OFF")
        model.menuBarRevealed = false
        render()
        control.performClick(nil)
        render()
        precondition(control.state == .off && model.menuState.layoutPending)
        precondition(model.menuState.progressDescription == "正在展开状态栏…")
        completions[2](nil)
        render()
        precondition(control.state == .off && control.isEnabled)
        print("Native switch feedback rendered in \(String(format: "%.1f", feedbackMs))ms with backend completion blocked; rollback, success, reveal and OFF passed; window never shown")
    }
}
