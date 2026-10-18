import AppKit

/// Version selection is deliberately explicit. A future compositor must not
/// inherit an unverified geometry trick just because its version is larger.
enum MenuBarCompatibility: String {
    case legacy26
    case native27
    case unavailable

    static func policy(majorVersion: Int) -> Self {
        switch majorVersion {
        case 26: return .legacy26
        case 27: return .native27
        default: return .unavailable
        }
    }

    var failureMessage: String {
        switch self {
        case .legacy26: return "系统没有完成折叠，已恢复展开。状态栏排列未生效，请重新打开 Hasp 后重试。"
        case .native27: return "系统没有完成折叠，已尝试恢复。请在权限页检查菜单栏配置访问和辅助功能权限。"
        case .unavailable: return "当前 macOS 版本的状态栏折叠尚未适配，已保持展开。外观、声音和蓝牙功能仍可使用。"
        }
    }
}

@MainActor protocol MenuBarFoldItem: AnyObject {
    var length: CGFloat { get set }
    var isVisible: Bool { get set }
}

extension NSStatusItem: MenuBarFoldItem {}

/// Coalesce rapid intents and leave the click handler before asking AppKit
/// to resize a native menu-bar scene on the main actor.
@MainActor final class MenuBarLayoutRequests {
    private var desired: Bool?
    private var queued = false
    private let apply: (Bool) -> Void

    init(apply: @escaping (Bool) -> Void) { self.apply = apply }

    func submit(_ folded: Bool) {
        desired = folded
        guard !queued else { return }
        queued = true
        Task { [self] in
            await Task.yield()
            while let value = desired {
                desired = nil
                apply(value)
            }
            queued = false
        }
    }
}

/// Only the divider expands. An unfolded divider is removed from the bar,
/// rather than leaving a transparent icon-sized gap beside the native entry.
enum MenuBarFoldLayout {
    static let entryWidth: CGFloat = 24
    static let restingDividerWidth: CGFloat = 24
    static let foldedWidth: CGFloat = 10_000

    @MainActor static func apply<Item: MenuBarFoldItem>(
        _ folded: Bool, to divider: Item,
        name: String = "hasp.divider", defaults: UserDefaults = .standard
    ) {
        let positionKey = "NSStatusItem Preferred Position \(name)"
        if folded {
            // Set the final width while hidden, so reinsertion doesn't first
            // expose a normal-width blank item. The entry's host never moves.
            if divider.length != foldedWidth { divider.length = foldedWidth }
            if !divider.isVisible { divider.isVisible = true }
        } else if divider.isVisible {
            // AppKit deletes the saved position when removing an item. Restore
            // it immediately so reinsertion stays beside Hasp, not at the far left.
            let position = defaults.object(forKey: positionKey) ?? 1
            divider.isVisible = false
            defaults.set(position, forKey: positionKey)
        }
    }
}

/// macOS 27 drops an oversized status item instead of using it to displace
/// its neighbours. Bound each part by the smallest menu-bar area, including
/// the trailing area of a notched display, and cover the widest display.
struct MenuBarFoldGeometry {
    struct Display {
        var width: CGFloat
        var trailingWidth: CGFloat? = nil
    }

    static let maximumParts = 16

    static func parts(for displays: [Display]) -> [CGFloat]? {
        guard !displays.isEmpty,
              displays.allSatisfy({ $0.width.isFinite && $0.width > 0 &&
                  ($0.trailingWidth == nil || ($0.trailingWidth!.isFinite && $0.trailingWidth! > 0)) }) else { return nil }
        let narrowest = displays.map { min($0.width, $0.trailingWidth ?? $0.width) }.min()!
        let unit = floor(narrowest / 2) - 64
        guard unit >= 32 else { return nil }
        let widest = displays.map(\.width).max()!
        let required = ceil((widest + 64) / unit)
        guard required.isFinite, required <= CGFloat(maximumParts) else { return nil }
        let count = Int(required)
        return Array(repeating: unit, count: count)
    }

    /// A saved preference is not evidence of the current native order.
    static func placementIssue(entry: CGRect?, divider: CGRect?, display: CGRect, visibleItems: [CGRect]) -> String? {
        guard let entry, let divider, !entry.isEmpty, !divider.isEmpty,
              !display.isEmpty, display.contains(CGPoint(x: entry.midX, y: entry.midY)),
              abs(entry.midY - divider.midY) < 12 else {
            return "状态栏位置尚未就绪，请稍后重试。"
        }
        guard divider.maxX <= entry.minX + 2, entry.minX - divider.maxX <= 32 else {
            return "折叠边界与 Hasp 的位置不相邻，请恢复两者相邻的顺序后重试。"
        }
        if visibleItems.contains(where: {
            !$0.isEmpty && display.contains(CGPoint(x: $0.midX, y: $0.midY)) &&
                abs($0.midY - entry.midY) < 16 && $0.maxX > divider.minX + 2
        }) {
            return "首次配置：请按住 ⌘，将要收起的应用图标拖到「折叠边界」左侧，保持边界与 Hasp 的顺序，然后重试。"
        }
        return nil
    }
}
