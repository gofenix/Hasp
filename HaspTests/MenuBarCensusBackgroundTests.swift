import AppKit
import Foundation

// Regression for the actual detached census used when folding the menu bar.
// Run on a logged-in Mac with Accessibility enabled for the test host and an
// input-source menu-bar item. No menu-bar state or foreground window is changed.
@main
enum MenuBarCensusBackgroundTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        guard MenuBarCensus.isTrusted else {
            fputs("Accessibility permission is required for this integration test.\n", stderr)
            exit(2)
        }
        _ = MenuBarCensus.thirdPartyIcons()
        var finished = false
        Task.detached {
            let icons = MenuBarCensus.thirdPartyIcons()
            guard icons.contains(where: { $0.id == "com.apple.TextInputMenuAgent" && !$0.name.isEmpty }) else {
                fputs("The input-source menu-bar item is required to exercise the regression.\n", stderr)
                exit(2)
            }
            DispatchQueue.main.async {
                print("Background menu-bar census passed: \(icons.count) entries.")
                finished = true
            }
        }
        let deadline = Date().addingTimeInterval(30)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if !finished {
            fputs("Background census did not complete.\n", stderr)
            exit(1)
        }
    }
}
