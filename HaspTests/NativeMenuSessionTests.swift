import Foundation

@main
enum NativeMenuSessionTests {
    static func main() {
        var state = NativeMenuSessionState()
        expect(!state.shouldFinish(presentationVisible: false), "wait for an asynchronous menu instead of folding before it opens")
        state.menuOpened()
        for _ in 0..<200 {
            expect(!state.shouldFinish(presentationVisible: true), "a menu open beyond the old 12 second deadline must remain available")
        }
        state.menuOpened()
        state.menuClosed()
        expect(!state.shouldFinish(presentationVisible: false), "closing a submenu must not close the parent")
        state.menuClosed()
        expect(!state.shouldFinish(presentationVisible: false), "allow a menu replacement to settle")
        expect(!state.shouldFinish(presentationVisible: false), "second settling sample")
        expect(state.shouldFinish(presentationVisible: false), "restore after the final menu disappears")

        var popover = NativeMenuSessionState()
        expect(!popover.shouldFinish(presentationVisible: true), "custom popovers without AX menu notifications are tracked")
        expect(!popover.shouldFinish(presentationVisible: true, outsideInteraction: true), "do not fold while a menu still processes its dismissal")
        expect(popover.shouldFinish(presentationVisible: false, outsideInteraction: true), "Esc or an outside click finishes after dismissal")

        var actionOnly = NativeMenuSessionState()
        for _ in 0..<200 {
            expect(!actionOnly.shouldFinish(visibility: .absent), "missing startup evidence must not create an automatic dismissal deadline")
            expect(!actionOnly.shouldFinish(visibility: .unknown), "unobservable menus must stay available")
        }
        expect(actionOnly.shouldFinish(presentationVisible: false, outsideInteraction: true), "actions with no exposed menu still restore on the next outside interaction")

        var uncertain = NativeMenuSessionState()
        expect(!uncertain.shouldFinish(visibility: .visible), "observe the menu")
        for _ in 0..<200 {
            expect(!uncertain.shouldFinish(visibility: .unknown), "AX timeouts after opening are not a menu-close signal")
        }
        expect(!uncertain.shouldFinish(visibility: .absent), "start a fresh dismissal confirmation after an unknown period")
        expect(!uncertain.shouldFinish(visibility: .unknown), "unknown resets an incomplete dismissal confirmation")
        expect(!uncertain.shouldFinish(visibility: .absent), "absence must be consecutive")

        var duplicate = NativeMenuSessionState()
        duplicate.menuOpened(id: 100)
        duplicate.menuOpened(id: 100)
        expect(duplicate.menuDepth == 1, "duplicate observers must not inflate menu depth")
        duplicate.menuOpened(id: 200)
        duplicate.menuClosed(id: 200)
        expect(!duplicate.shouldFinish(visibility: .absent), "the parent's distinct menu identity remains open")
        duplicate.menuClosed(id: 100)
        expect(duplicate.menuDepth == 0, "a single close matches duplicated open notifications")
        print("Native menu lifetime tests passed.")
    }

    private static func expect(_ result: Bool, _ message: String) {
        if !result { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
