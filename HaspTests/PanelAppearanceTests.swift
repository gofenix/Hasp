import AppKit
import SwiftUI

@main
enum PanelAppearanceTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let host = NSHostingController(rootView: Text("Hasp"))
        let popover = NSPopover()
        popover.contentViewController = host
        let parent = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        parent.contentView = host.view
        // Reproduce a light status-bar host with dark app content, without
        // showing a window or changing the user's system appearance.
        parent.appearance = NSAppearance(named: .aqua)
        PanelAppearance.apply(dark: true, to: popover)
        precondition(popover.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        precondition(host.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        // Theme changes must update both material and contents in either direction.
        parent.appearance = NSAppearance(named: .darkAqua)
        PanelAppearance.apply(dark: false, to: popover)
        precondition(popover.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        precondition(host.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        PanelAppearance.apply(dark: true, to: popover)
        precondition(host.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        print("ok: popover and SwiftUI appearances match despite opposite host appearance; light/dark updates pass")
    }
}
