import AppKit
import Foundation

// Regression for the actual detached census used when folding the menu bar.
// Run on a logged-in Mac with Accessibility enabled for the test host and an
// input-source menu-bar item. No menu-bar state or foreground window is changed.
@main
enum MenuBarCensusBackgroundTests {
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        guard MenuBarCensus.isTrusted else {
            fputs("Accessibility permission is required for this integration test.\n", stderr)
            exit(2)
        }
        _ = MenuBarCensus.thirdPartyIcons()
        let icons = await Task.detached { MenuBarCensus.thirdPartyIcons() }.value
        guard icons.contains(where: { $0.target?.bundleIdentifier == "com.apple.TextInputMenuAgent" && !$0.name.isEmpty }) else {
            fputs("The input-source menu-bar item is required to exercise the regression.\n", stderr)
            exit(2)
        }
        precondition(!icons.isEmpty)
        precondition(Set(icons.map(\.id)).count == icons.count)
        print("Background menu-bar census passed: \(icons.count) entries.")
    }
}
