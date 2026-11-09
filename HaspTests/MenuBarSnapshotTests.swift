import AppKit
import Observation
import Foundation
import SwiftUI

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

@MainActor final class MenuScanGate {
    var reads = 0
    var transitions: [(Bool, () -> Void)] = []
    private var pending: [CheckedContinuation<[MenuBarIcon], Never>] = []
    func read() async -> [MenuBarIcon] {
        reads += 1
        return await withCheckedContinuation { pending.append($0) }
    }
    func release(_ icons: [MenuBarIcon]) { pending.removeFirst().resume(returning: icons) }
    var services: MenuBarServices {
        MenuBarServices(snapshot: { await self.read() }, transition: {
            self.transitions.append(($0, $1))
        }, isTrusted: { true }, requestAccess: { preconditionFailure("Must not request permission in this test") })
    }
}

@main enum MenuBarSnapshotTests {
    @MainActor static func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            precondition(Date() < deadline, "Scan timed out")
            try! await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "app.hasp.menu.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = MenuScanGate()
        let model = AppModel(store: SettingsStore(defaults: defaults), menuServices: gate.services)
        let complete = [MenuBarIcon(id: "magpie", name: "magpie"),
                        MenuBarIcon(id: "lark", name: "飞书"),
                        MenuBarIcon(id: "system.WiFi", name: "Wi-Fi")]
        var publications: [[String]] = []
        var visualFolds: [Bool] = []
        model.setMenuBarSpacer = { visualFolds.append($0) }
        let observer = StateObservation(read: { _ = model.menuBarIcons }, didChange: { publications.append(model.menuBarIcons.map(\.id)) })

        // A slow first census may have system placeholders available already,
        // but the actual fold callback must not publish a half-list.
        model.setMenuBarFolded(true)
        precondition(visualFolds == [true], "Native folding must not wait for preference writes")
        precondition(gate.transitions.count == 1 && gate.transitions[0].0)
        model.refreshMenuBarItems() // A timer during the transition cannot scan.
        precondition(gate.reads == 0)
        gate.transitions[0].1()
        await wait { gate.reads == 1 }
        precondition(model.menuState.refreshing && publications.isEmpty && model.menuBarIcons.isEmpty)
        gate.release(complete)
        await wait { !model.menuBarScanPending }
        await wait { publications.count == 1 }
        precondition(publications == [complete.map(\.id)], "Only the full list may be published")

        // OFF and a slow refresh retain the full cache. Identical snapshots
        // update native handles but send no extra list publication.
        model.setMenuBarFolded(false)
        gate.transitions[1].1()
        await wait { gate.reads == 2 }
        precondition(model.menuBarIcons == complete && !model.menuBarFolded)
        precondition(!model.menuState.refreshing, "Warm refresh must not publish a loading state")
        gate.release(complete)
        await wait { !model.menuBarScanPending }
        precondition(publications.count == 1)

        var warmSignals = 0
        let warmObserver = StateObservation(read: { model.trackPanelPresentation() }, didChange: { warmSignals += 1 })
        model.refreshMenuBarItems(force: false)
        precondition(!model.menuBarScanPending && gate.reads == 2, "A fresh cache must skip repeated open/timer scans")
        model.refreshMenuBarItems()
        await wait { gate.reads == 3 }
        gate.release(complete)
        await wait { !model.menuBarScanPending }
        try! await Task.sleep(for: .milliseconds(10))
        precondition(warmSignals == 0, "An identical warm scan must not invalidate the menu section")

        // An old unfolded scan cannot overwrite a newer fold. It is discarded
        // and exactly one fresh scan runs after the transition completes.
        model.refreshMenuBarItems()
        await wait { gate.reads == 4 }
        model.setMenuBarFolded(true)
        gate.transitions[2].1()
        gate.release([MenuBarIcon(id: "stale", name: "stale")])
        await wait { gate.reads == 5 }
        precondition(model.menuBarIcons == complete && publications.count == 1)
        let updated = complete.map { icon in
            var next = icon
            next.status = icon.id == "lark" ? "1 条通知" : nil
            return next
        }
        gate.release(updated)
        await wait { !model.menuBarScanPending }
        await wait { publications.count == 2 }
        precondition(model.menuBarIcons == updated && publications.count == 2)

        // Rapid ON/OFF callbacks arrive out of order; only the newest can
        // clear the transition barrier and start a scan.
        model.setMenuBarFolded(false)
        model.setMenuBarFolded(true)
        gate.transitions[3].1()
        model.refreshMenuBarItems()
        precondition(gate.reads == 5)
        gate.transitions[4].1()
        await wait { gate.reads == 6 }
        gate.release(updated)
        await wait { !model.menuBarScanPending }
        precondition(publications.count == 2)

        // A second model warms its complete cache before any fold/first open.
        let warmGate = MenuScanGate()
        let warm = AppModel(store: SettingsStore(defaults: defaults), menuServices: warmGate.services)
        warm.refreshMenuBarItems()
        await wait { warmGate.reads == 1 }
        warmGate.release(complete)
        await wait { !warm.menuBarScanPending }
        precondition(!warm.menuBarFolded && warm.menuBarIcons == complete)

        // Real layout completion is distinct from requested state. Native
        // failure rolls back both the switch and system preferences. A stale
        // failure must not undo a newer OFF or a newer successful fold.
        var nativeCompletions: [(MenuBarLayoutFailure?) -> Void] = []
        var preferenceIntents: [Bool] = []
        let checked = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { complete }, transition: { on, done in preferenceIntents.append(on); done() },
            isTrusted: { true }, requestAccess: { preconditionFailure() }))
        checked.applyMenuBarLayout = { _, done in nativeCompletions.append(done) }
        checked.setMenuBarFolded(true)
        precondition(checked.menuState.layoutPending)
        nativeCompletions[0]("位置不正确")
        precondition(!checked.menuBarFolded && !checked.menuState.layoutPending)
        precondition(checked.menuBarMessage == "位置不正确" && preferenceIntents == [true, false])
        checked.setMenuBarFolded(true)
        checked.setMenuBarFolded(false)
        nativeCompletions[1]("过期的失败")
        precondition(!checked.menuBarFolded && checked.menuBarMessage == nil)
        checked.setMenuBarFolded(true)
        nativeCompletions[3](nil)
        nativeCompletions[1]("更早的失败")
        precondition(checked.menuBarFolded && !checked.menuState.layoutPending && checked.menuBarMessage == nil)
        checked.setMenuBarFolded(true)
        checked.setMenuBarFolded(false)
        checked.setMenuBarFolded(true)
        nativeCompletions[4](nil)
        precondition(checked.menuState.layoutPending, "An old success cannot confirm the new pending request")
        nativeCompletions[6]("新请求失败")
        precondition(!checked.menuBarFolded && checked.menuBarMessage == "新请求失败")
        var unsupportedPreferences: [Bool] = []
        let unsupported = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { complete }, transition: { on, done in unsupportedPreferences.append(on); done() },
            isTrusted: { true }, requestAccess: { preconditionFailure() }))
        unsupported.applyMenuBarLayout = { _, done in done(MenuBarLayoutFailure(MenuBarCompatibility.unavailable.failureMessage)) }
        unsupported.setMenuBarFolded(true)
        precondition(!unsupported.menuBarFolded && !unsupported.menuState.layoutPending)
        precondition(unsupportedPreferences == [false], "An immediate unsupported-version failure must never enqueue a later hide")

        var modernPreferences: [Bool] = []
        var modernCallbacks: [(MenuBarLayoutFailure?) -> Void] = []
        let modern = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { [] }, transition: { on, done in modernPreferences.append(on); done() },
            isTrusted: { true }, requestAccess: { preconditionFailure() }, waitsForLayout: true))
        modern.applyMenuBarLayout = { _, done in modernCallbacks.append(done) }
        modern.setMenuBarFolded(true)
        precondition(modernPreferences.isEmpty && modern.menuState.layoutPending, "Never flash system icons before native access/verification succeeds")
        modernCallbacks[0]("需要菜单栏配置访问")
        precondition(modernPreferences == [false] && !modern.menuBarFolded)
        modern.setMenuBarFolded(true)
        precondition(modernPreferences == [false])
        modernCallbacks[1](nil)
        precondition(modernPreferences == [false, true] && modern.menuBarFolded)
        modern.setMenuBarFolded(false)
        precondition(modern.menuState.layoutPending && modernPreferences == [false, true])
        modernCallbacks[2](MenuBarLayoutFailure("恢复失败", stillFolded: true))
        precondition(modern.menuBarFolded && !modern.menuState.layoutPending && modern.menuBarMessage == "恢复失败")
        precondition(modern.menuState.recoveryPending, "An unconfirmed restore must show recovery UI, not claim successful folding")
        precondition(modernPreferences == [false, true, true], "Failed restoration must not report a successful OFF")
        modern.setMenuBarFolded(false)
        modernCallbacks[3](nil)
        precondition(!modern.menuBarFolded && modernPreferences == [false, true, true, false])
        precondition(!modern.menuState.recoveryPending)
        let noAccess = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { [] }, transition: { _, _ in preconditionFailure("Cannot hide system modules without AX") },
            isTrusted: { false }, requestAccess: { preconditionFailure("No automatic prompt or app activation") }, waitsForLayout: true))
        noAccess.applyMenuBarLayout = { _, _ in preconditionFailure("Cannot hide apps without AX") }
        noAccess.setMenuBarFolded(true)
        precondition(!noAccess.menuBarFolded && noAccess.menuBarMessage != nil)

        // A coordinated live batch retains a complete warm snapshot. ON/OFF
        // must not schedule another census or invalidate rows just to toggle
        // native visibility. Cold-start behavior still populates the list.
        let cachedGate = MenuScanGate()
        var cachedServices = cachedGate.services
        cachedServices.refreshesAfterTransition = false
        let cached = AppModel(store: SettingsStore(defaults: defaults), menuServices: cachedServices)
        cached.menuBarIcons = complete
        cached.setMenuBarFolded(true)
        cachedGate.transitions[0].1()
        await Task.yield()
        precondition(cachedGate.reads == 0 && !cached.menuBarScanPending && cached.menuBarIcons == complete)
        cached.setMenuBarFolded(false)
        cachedGate.transitions[1].1()
        await Task.yield()
        precondition(cachedGate.reads == 0 && cached.menuBarIcons == complete)
        cached.menuBarIcons = []
        cached.setMenuBarFolded(true)
        cachedGate.transitions[2].1()
        await wait { cachedGate.reads == 1 }
        cachedGate.release(complete)
        await wait { !cached.menuBarScanPending }
        precondition(cached.menuBarIcons == complete)

        // Current prefs are all hidden by Hasp; use the original visibility
        // backup, not those temporary values. User-hidden modules stay absent.
        let backup = MenuBarPrefs.Backup(restore: ["WiFi": 18, "Sound": 18], bentoVisible: true)
        let folded = MenuBarPrefs.systemIconPlaceholders(backup: backup, value: { _ in 8 })
        precondition(folded.map(\.id) == ["system.WiFi", "system.Sound"])
        let unfolded = MenuBarPrefs.systemIconPlaceholders(backup: nil, value: { $0 == "Battery" ? 8 : 18 })
        precondition(unfolded.count == 3 && !unfolded.contains { $0.id == "system.Battery" })

        // An app that appears while folded is extended, never re-planned
        // through the full ON batch: a missing native record for one new app
        // would otherwise restore the whole bar.
        var extendRequests: [(ids: [String], pending: Set<String>)] = []
        var modernLayoutRequests = 0
        let growing = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { complete }, transition: { _, done in done() },
            extend: { icons, done in extendRequests.append((icons.map(\.id), [])); done(true, []) },
            isTrusted: { true }, requestAccess: { preconditionFailure() }, waitsForLayout: true))
        growing.menuBarIcons = complete
        growing.applyMenuBarLayout = { _, done in
            // Only the initial ON may use the full batch.
            if modernLayoutRequests == 0 { modernLayoutRequests += 1; done(nil) }
            else { preconditionFailure("A new icon must not re-run the full fold") }
        }
        growing.setMenuBarFolded(true)
        growing.refreshMenuBarItems()
        await wait { !growing.menuBarScanPending }
        precondition(extendRequests.isEmpty, "An unchanged list must not extend")
        growing.refreshMenuBarItems()
        await wait { !growing.menuBarScanPending }
        precondition(extendRequests.isEmpty && growing.menuBarIcons == complete)
        // A new icon arrives with the panel closed, exactly as the bug reports.
        let grown = complete + [MenuBarIcon(id: "newcomer", name: "Newcomer")]
        let grownModel = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { grown }, transition: { _, done in done() },
            extend: { icons, done in extendRequests.append((icons.map(\.id), [])); done(true, []) },
            isTrusted: { true }, requestAccess: { preconditionFailure() }, waitsForLayout: true))
        grownModel.menuBarIcons = complete
        grownModel.setMenuBarFolded(true)
        grownModel.refreshMenuBarItems()
        await wait { !grownModel.menuBarScanPending }
        await wait { !extendRequests.isEmpty }
        precondition(extendRequests.count == 1 && extendRequests[0].ids == ["newcomer"],
                     "Only the new icon may be extended, never the whole list")

        // The panel is closed here: an app launch event alone must trigger a
        // scan and extend, with no timer running.
        var launchedExtends: [[String]] = []
        var launchedReads = 0
        let eventDriven = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { launchedReads += 1; return grown },
            transition: { _, done in done() },
            extend: { icons, done in launchedExtends.append(icons.map(\.id)); done(true, []) },
            isTrusted: { true }, requestAccess: { preconditionFailure() }, waitsForLayout: true,
            refreshesAfterTransition: false))
        eventDriven.menuBarIcons = complete
        eventDriven.applyMenuBarLayout = { _, done in done(nil) }
        eventDriven.observeMenuBarEnvironment()
        eventDriven.setMenuBarFolded(true)
        eventDriven.panelDidClose()
        let readsBeforeEvent = launchedReads
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        await wait { !launchedExtends.isEmpty }
        precondition(launchedReads > readsBeforeEvent, "A launch event must trigger the census with the panel closed")
        precondition(launchedExtends == [["newcomer"]], "The event path must extend only the new icon")
        // Unfolding stops the reconciler: a later event must not scan.
        await wait { !eventDriven.menuBarScanPending }
        try! await Task.sleep(for: .milliseconds(50))
        eventDriven.setMenuBarFolded(false)
        let readsAfterUnfold = launchedReads
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        try! await Task.sleep(for: .milliseconds(700))
        precondition(launchedReads == readsAfterUnfold, "An unfolded bar must not scan on app events")

        // No event, no scan: a folded bar with no lifecycle observer cannot
        // reach a census by itself, so any read here would be a timer.
        var idleReads = 0
        let idle = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { idleReads += 1; return complete }, transition: { _, done in done() },
            isTrusted: { true }, requestAccess: { preconditionFailure() }, waitsForLayout: true,
            refreshesAfterTransition: false))
        idle.menuBarIcons = complete
        idle.applyMenuBarLayout = { _, done in done(nil) }
        idle.setMenuBarFolded(true)
        await wait { !idle.menuBarScanPending }
        try! await Task.sleep(for: .milliseconds(1500))
        precondition(idleReads == 0, "A folded bar must not poll without an event")

        // A burst of events coalesces into one census rather than one each.
        var burstReads = 0
        let burst = AppModel(store: SettingsStore(defaults: defaults), menuServices: MenuBarServices(
            snapshot: { burstReads += 1; return complete }, transition: { _, done in done() },
            isTrusted: { true }, requestAccess: { preconditionFailure() }, waitsForLayout: true,
            refreshesAfterTransition: false))
        burst.menuBarIcons = complete
        burst.applyMenuBarLayout = { _, done in done(nil) }
        burst.observeMenuBarEnvironment()
        burst.setMenuBarFolded(true)
        for _ in 0..<5 {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didActivateApplicationNotification, object: nil)
        }
        await wait { burstReads > 0 }
        try! await Task.sleep(for: .milliseconds(400))
        precondition(burstReads == 1, "A burst of events must coalesce into one census")

        // Measure the real panel in an unshown window. A single overall
        // viewport now bounds all expanded content to the available height.
        func panelSize() -> NSSize {
            let view = NSHostingView(rootView: PanelView(maximumHeight: 540).environment(model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            for _ in 0..<4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                view.layoutSubtreeIfNeeded()
                window.setContentSize(view.fittingSize)
            }
            precondition(!window.isVisible)
            return view.fittingSize
        }
        model.menuBarIcons = []
        model.menuState.refreshing = true
        let loadingSize = panelSize()
        model.menuBarIcons = complete
        model.menuState.refreshing = false
        let shortSize = panelSize()
        model.menuBarIcons = (0..<30).map { MenuBarIcon(id: "app.\($0)", name: "App \($0)", status: "通知") }
        let fullSize = panelSize()
        precondition([loadingSize, shortSize, fullSize].allSatisfy { $0.height <= 540 && $0.height > 100 })
        model.menuBarFolded = false
        let unfoldedSize = panelSize()
        precondition(unfoldedSize.height < fullSize.height, "Hidden menu rows must occupy zero content height")
        model.menuBarFolded = true
        precondition(abs(panelSize().height - fullSize.height) < 1)
        withExtendedLifetime([observer, warmObserver]) {}
        print("Menu snapshots passed: native fold dispatched before preference completion; identical warm scan publishes 0 signals; fresh cache skips scan; atomic and stale results; expanded panel remains within 540pt.")
    }
}
