import Foundation

enum NativeMenuVisibility { case visible, absent, unknown }

/// Missing or timed-out accessibility data is not proof of dismissal.
struct NativeMenuSessionState {
    private var menus = Set<UInt64>()
    var menuDepth: Int { menus.count }
    private(set) var didPresent = false
    private(set) var didReceiveClose = false
    private var emptySamples = 0
    private var nextToken: UInt64 = 0

    mutating func menuOpened() {
        nextToken += 1
        menuOpened(id: nextToken)
    }

    mutating func menuOpened(id: UInt64) {
        menus.insert(id)
        didPresent = true
        didReceiveClose = false
        emptySamples = 0
    }

    mutating func menuClosed() {
        if let id = menus.first { menuClosed(id: id) }
    }

    mutating func menuClosed(id: UInt64) {
        menus.remove(id)
        didPresent = true
        didReceiveClose = true
    }

    mutating func shouldFinish(presentationVisible: Bool, outsideInteraction: Bool = false) -> Bool {
        shouldFinish(visibility: presentationVisible ? .visible : .absent, outsideInteraction: outsideInteraction)
    }

    mutating func shouldFinish(visibility: NativeMenuVisibility, outsideInteraction: Bool = false) -> Bool {
        if visibility == .visible {
            didPresent = true
            emptySamples = 0
            return false
        }
        if visibility == .unknown {
            emptySamples = 0
            return outsideInteraction && menuDepth == 0
        }
        if outsideInteraction { return true }
        if menuDepth > 0 { return false }
        guard didPresent else { return false }
        emptySamples += 1
        // Avoid folding between removal of a submenu and its replacement.
        return emptySamples >= 3
    }
}
