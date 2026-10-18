import AppKit

enum PanelAppearance {
    @MainActor
    static func apply(dark: Bool, to popover: NSPopover) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
    }
}
