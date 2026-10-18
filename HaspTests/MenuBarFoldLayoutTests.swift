import AppKit
import Foundation

@MainActor final class FakeFoldItem: MenuBarFoldItem {
    var updates = 0
    var length: CGFloat = 24 { didSet { updates += 1 } }
    var visibilityUpdates = 0
    var onHide: (() -> Void)?
    var onShow: (() -> Void)?
    var isVisible = true {
        didSet {
            visibilityUpdates += 1
            if isVisible { onShow?() } else { onHide?() }
        }
    }
}

@main enum MenuBarFoldLayoutTests {
    @MainActor static func main() async {
        precondition(MenuBarCompatibility.policy(majorVersion: 26) == .legacy26)
        precondition(MenuBarCompatibility.policy(majorVersion: 27) == .native27)
        for version in [0, 14, 25, 28, 99] {
            precondition(MenuBarCompatibility.policy(majorVersion: version) == .unavailable)
        }
        precondition(!MenuBarCompatibility.legacy26.failureMessage.contains("折叠边界"), "Legacy failures cannot ask for a hidden modern-only marker")
        let entry = FakeFoldItem()
        let divider = FakeFoldItem()
        let suite = "HaspFoldLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "NSStatusItem Preferred Position hasp.divider"
        defaults.set(1, forKey: key)
        divider.onHide = { defaults.removeObject(forKey: key) }
        divider.onShow = {
            precondition(defaults.integer(forKey: key) == 1, "Restore position before reinsertion")
            precondition(divider.length == 10_000, "Reinsert at the final folded width")
        }
        MenuBarFoldLayout.apply(false, to: divider, defaults: defaults)
        precondition(!divider.isVisible, "Startup must leave no blank slot")
        for _ in 0..<100 {
            MenuBarFoldLayout.apply(true, to: divider, defaults: defaults)
            MenuBarFoldLayout.apply(true, to: divider, defaults: defaults)
            precondition(divider.length == 10_000)
            precondition(divider.isVisible)
            precondition(entry.length == MenuBarFoldLayout.entryWidth)
            MenuBarFoldLayout.apply(false, to: divider, defaults: defaults)
            MenuBarFoldLayout.apply(false, to: divider, defaults: defaults)
            precondition(!divider.isVisible)
            precondition(defaults.integer(forKey: key) == 1)
            precondition(entry.length == MenuBarFoldLayout.entryWidth)
        }
        precondition(entry.updates == 0, "Folding must never resize the popover's entry host")
        precondition(divider.updates == 1, "Keep the hidden divider's final width; don't resize twice per cycle")
        precondition(divider.visibilityUpdates == 201, "Same state must not relayout")
        var changes: [Bool] = []
        let requests = MenuBarLayoutRequests { changes.append($0) }
        for i in 0..<100 { requests.submit(i.isMultiple(of: 2)) }
        precondition(changes.isEmpty, "Native scene resizing must leave the click handler first")
        let deadline = Date().addingTimeInterval(2)
        while changes.isEmpty {
            precondition(Date() < deadline)
            try! await Task.sleep(for: .milliseconds(1))
        }
        precondition(changes == [false], "Only the latest rapid intent should resize the native scene")
        let displays: [MenuBarFoldGeometry.Display] = [.init(width: 1728, trailingWidth: 800), .init(width: 1152), .init(width: 1920)]
        let parts = MenuBarFoldGeometry.parts(for: displays)!
        precondition(parts.count > 1 && parts.count <= MenuBarFoldGeometry.maximumParts)
        precondition(parts.reduce(0, +) >= 1984, "Cover the widest screen, not just the narrowest")
        precondition(parts.allSatisfy { $0 < 400 }, "Each item must stay below half the smallest menu-bar area")
        precondition(MenuBarFoldGeometry.parts(for: []) == nil)
        precondition(MenuBarFoldGeometry.parts(for: [.init(width: 0)]) == nil)
        precondition(MenuBarFoldGeometry.parts(for: [.init(width: .infinity)]) == nil)
        precondition(MenuBarFoldGeometry.parts(for: [.init(width: 500), .init(width: 100_000)]) == nil)
        precondition(MenuBarFoldGeometry.parts(for: [.init(width: 500), .init(width: .greatestFiniteMagnitude)]) == nil)
        // Recalculate for unplug/replug, scaling and rotated displays; never
        // carry a wide display's unsafe unit onto a newly narrower one.
        for topology: [MenuBarFoldGeometry.Display] in [
            [.init(width: 1920)], [.init(width: 1920), .init(width: 1152)],
            [.init(width: 1728, trailingWidth: 770)], [.init(width: 1024)],
            [.init(width: 1440), .init(width: 3840)], [.init(width: 1152), .init(width: 1920)]
        ] {
            let recalculated = MenuBarFoldGeometry.parts(for: topology)!
            let limit = topology.map { min($0.width, $0.trailingWidth ?? $0.width) / 2 }.min()!
            precondition(recalculated.allSatisfy { $0 < limit })
            precondition(recalculated.reduce(0, +) >= topology.map(\.width).max()!)
        }
        let screen = CGRect(x: 1728, y: 37, width: 1920, height: 1080)
        let entryRect = CGRect(x: 3407, y: 1084, width: 40, height: 33)
        let adjacent = CGRect(x: 3367, y: 1084, width: 40, height: 33)
        func issue(_ divider: CGRect?, _ icons: [CGRect] = []) -> String? {
            MenuBarFoldGeometry.placementIssue(entry: entryRect, divider: divider, display: screen, visibleItems: icons)
        }
        precondition(issue(adjacent) == nil)
        precondition(issue(CGRect(x: -1368, y: 1084, width: 5016, height: 33)) != nil, "Reject the user's detached-divider layout")
        precondition(issue(adjacent, [CGRect(x: 3480, y: 1084, width: 30, height: 24)]) != nil, "Do not hide only a subset and claim all folded")
        precondition(issue(adjacent, [CGRect(x: 4700, y: 1084, width: 30, height: 24)]) == nil, "A different display is not a misplaced neighbour")
        precondition(issue(nil) != nil)
        print("Fold layout passed: no unfolded placeholder; position survives 100 removals; fixed native entry; rapid requests coalesce.")
    }
}
