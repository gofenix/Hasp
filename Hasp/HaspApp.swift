import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private static let compatibility = MenuBarCompatibility.policy(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    private static let modern = compatibility != .legacy26
    private static var iconName: String { modern ? "hasp.entry.v27" : "hasp.icon" }
    private static var dividerName: String { modern ? "hasp.fold-boundary.v27" : "hasp.divider" }
    private let statusItem: NSStatusItem
    private let divider: NSStatusItem
    private let foldParts: [NSStatusItem]
    private let popover = NSPopover()
    private let panelDismissMonitor = PanelDismissMonitor()
    private let model: AppModel
    private var afterDismiss: (() -> Void)?
    private var appearanceSubscription: AnyCancellable?
    private var preparationSubscriptions = Set<AnyCancellable>()
    private var preparationQueued = false
    private var updatePanelLimit: ((CGFloat) -> Void)?
    private var layoutTask: Task<Void, Never>?
    private var layoutGeneration = 0

    init(model: AppModel) {
        self.model = model
        // Keep the entry at a normal width; expanding its host breaks native
        // popover positioning across menu-bar scenes on multiple displays.
        if !Self.modern { Self.pin(Self.iconName, position: 0) }
        statusItem = NSStatusBar.system.statusItem(withLength: MenuBarFoldLayout.entryWidth)
        statusItem.autosaveName = Self.iconName
        // On 27 the menu-bar agent owns ordering. The old defaults no longer
        // position items; register fresh identities once, in creation order.
        foldParts = [] // macOS 27 uses native per-app visibility, no spacers.
        if !Self.modern { Self.pin(Self.dividerName, position: 1) }
        divider = NSStatusBar.system.statusItem(withLength: MenuBarFoldLayout.restingDividerWidth)
        divider.autosaveName = Self.dividerName
        divider.button?.image = NSImage(size: NSSize(width: 1, height: 1))
        divider.button?.toolTip = "折叠边界：按住 ⌘ 将要折叠的应用图标移到此标记左侧"
        divider.button?.setAccessibilityLabel("折叠边界")
        // Register at a positive width first; a zero-width birth loses the
        // saved position on Tahoe. Then remove the unfolded placeholder.
        if Self.modern { divider.isVisible = false }
        else { MenuBarFoldLayout.apply(false, to: divider, name: Self.dividerName) }
        super.init()
        let button = statusItem.button
        button?.image = HaspGlyph.menuBarImage
        button?.toolTip = "Hasp"
        button?.target = self
        button?.action = #selector(togglePopover)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.applyMenuBarLayout = { [weak self] collapsed, completion in
            guard let self else { completion("状态栏控制器不可用，请重新打开 Hasp。"); return }
            self.setSpacer(collapsed, completion: completion)
        }
        model.dismissPanel = { [weak self] completion in
            guard let self, self.popover.isShown else { completion(); return }
            self.afterDismiss = completion
            self.popover.animates = false
            self.popover.performClose(nil)
        }
        model.presentPanel = { [weak self] in self?.showPopoverWhenReady() }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView().environmentObject(model))
        updatePanelLimit = { [weak host] height in
            host?.rootView = PanelView(maximumHeight: height).environmentObject(model)
        }
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        // Status-bar windows can inherit a light appearance from the bar's
        // backdrop while SwiftUI follows the system's dark appearance. Keep
        // the material and its content in the same appearance domain.
        appearanceSubscription = model.appearanceState.$isDark.removeDuplicates().sink { [weak self] dark in
            self?.updateAppearance(dark: dark)
        }
        // Prepare changed cached contents while closed. Coalesce publisher
        // bursts and defer until the model has finished assigning its fields.
        for publisher in [model.appearanceState.objectWillChange, model.audioState.objectWillChange,
                          model.deviceState.objectWillChange, model.menuState.objectWillChange] {
            publisher.sink { [weak self] _ in self?.preparePanelSoon() }
                .store(in: &preparationSubscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard Self.compatibility == .legacy26, let self, self.model.menuBarFolded, !self.model.menuBarRevealed else { return }
                self.model.setMenuBarFolded(true)
            }.store(in: &preparationSubscriptions)
        preparePanelSoon()
    }

    func setSpacer(_ collapsed: Bool, completion: @escaping (MenuBarLayoutFailure?) -> Void) {
        layoutGeneration += 1
        let generation = layoutGeneration
        layoutTask?.cancel()
        if Self.compatibility == .native27 {
            ModernMenuBarFold.shared.apply(collapsed, icons: model.menuBarIcons, completion: completion)
            return
        }
        guard collapsed else {
            expandLayout(showBoundary: false)
            completion(nil)
            return
        }
        guard Self.compatibility != .unavailable else {
            expandLayout(showBoundary: false)
            completion(MenuBarLayoutFailure(Self.compatibility.failureMessage))
            return
        }
        layoutTask = Task { [weak self] in
            await Task.yield() // leave the click handler before native layout
            guard let self, !Task.isCancelled else { return }
            var targets = self.model.menuBarIcons.filter { !$0.id.hasPrefix("system.") }.compactMap(\.target)
            if targets.isEmpty {
                targets = await Task.detached { MenuBarCensus.thirdPartyIcons().compactMap(\.target) }.value
            }
            guard !Task.isCancelled, generation == self.layoutGeneration else { return }
            MenuBarFoldLayout.apply(true, to: self.divider, name: Self.dividerName)
            // isVisible is registration state, not proof that neighbours moved.
            // Allow native layout to settle, then inspect real AX positions.
            var confirmed = false
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, generation == self.layoutGeneration else { return }
                let frames = await self.foreignFrames(targets: targets)
                guard !Task.isCancelled, generation == self.layoutGeneration else { return }
                if let frames, self.foldIsEffective(frames: frames) { confirmed = true; break }
            }
            if !confirmed { self.expandLayout(showBoundary: Self.modern) }
            if CommandLine.arguments.contains("--diagnose-menu-layout") { self.reportLayout() }
            completion(confirmed ? nil : MenuBarLayoutFailure(Self.compatibility.failureMessage))
        }
    }

    private func expandLayout(showBoundary: Bool) {
        for part in foldParts { part.isVisible = false; part.length = 0 }
        if Self.modern {
            divider.length = MenuBarFoldLayout.restingDividerWidth
            divider.button?.image = showBoundary ? NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "折叠边界") : nil
            divider.isVisible = showBoundary
        } else {
            MenuBarFoldLayout.apply(false, to: divider, name: Self.dividerName)
        }
    }

    private func foreignFrames(targets: [MenuBarTarget]) async -> [CGRect]? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frames = await Task.detached { MenuBarCensus.visibleItemFrames(targets: targets) }.value
        return frames?.map { CGRect(x: $0.minX, y: top - $0.maxY, width: $0.width, height: $0.height) }
    }

    private func foldIsEffective(frames: [CGRect]) -> Bool {
        guard MenuBarCensus.isTrusted, let entry = statusItem.button?.window?.frame,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: entry.midX, y: entry.midY)) }),
              divider.isVisible else { return false }
        // Hidden AX nodes can remain available off-screen or in an overflow
        // menu. Count only ordinary icon rectangles in this display's top strip.
        return !frames.contains { frame in
            frame.intersects(screen.frame) && frame.width < screen.frame.width / 2 &&
                abs(frame.midY - entry.midY) < 16
        }
    }

    private static func pin(_ name: String, position: Double) {
        UserDefaults.standard.set(position, forKey: "NSStatusItem Preferred Position \(name)")
    }

    private func preparePanelSoon() {
        guard !popover.isShown, !preparationQueued else { return }
        preparationQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.preparationQueued = false
            guard !self.popover.isShown, let view = self.popover.contentViewController?.view else { return }
            let start = DispatchTime.now().uptimeNanoseconds
            view.layoutSubtreeIfNeeded()
            _ = view.fittingSize
            SwitchTrace.duration("panel-prepare", since: start)
        }
    }

    func reportLayout() {
        func frame(_ item: NSStatusItem) -> [Double] {
            guard let rect = item.button?.window?.frame else { return [] }
            return [rect.minX, rect.minY, rect.width, rect.height]
        }
        let report: [String: Any] = ["itemFrame": frame(statusItem), "itemLength": statusItem.length,
                                   "buttonBounds": NSStringFromRect(statusItem.button?.bounds ?? .zero),
                                   "dividerFrame": frame(divider), "dividerLength": divider.length,
                                   "dividerVisible": divider.isVisible,
                                   "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                                   "compatibilityPolicy": Self.compatibility.rawValue,
                                   "segmentedLayout": false,
                                   "parts": foldParts.map { ["visible": $0.isVisible, "length": $0.length] as [String: Any] },
                                   "dividerPosition": UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(Self.dividerName)") ?? NSNull(),
                                   "savedPosition": UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(Self.iconName)") ?? NSNull()]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        fflush(stdout)
    }

    func showPopoverWhenReady(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let height = self.statusItem.button?.window?.frame.height ?? 0
            if height < 1 {
                if attempt < 30 {
                    self.showPopoverWhenReady(attempt: attempt + 1)
                }
                return
            }
            self.showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            let screenHeight = button.window?.screen?.visibleFrame.height ?? 792
            updatePanelLimit?(min(900, screenHeight - 72))
            updateAppearance(dark: model.isDark)
            popover.animates = false
            let start = DispatchTime.now().uptimeNanoseconds
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            SwitchTrace.duration("panel-show", since: start)
        }
    }

    private func updateAppearance(dark: Bool) {
        PanelAppearance.apply(dark: dark, to: popover)
    }

    @objc private func togglePopover() {
        guard statusItem.button != nil else { return }
        if popover.isShown {
            popover.animates = false
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        model.panelDidShow()
    }

    func popoverDidShow(_ notification: Notification) {
        panelDismissMonitor.start(isPanelWindow: { [weak self] window in
            guard let panel = self?.popover.contentViewController?.view.window else { return false }
            var candidate = window
            while let current = candidate {
                if current === panel { return true }
                candidate = current.parent
            }
            return false
        }, containsPanelPoint: { [weak self] point in
            self?.popover.contentViewController?.view.window?.frame.contains(point) ?? false
        }, containsEntryPoint: { [weak self] point in
            self?.entryContains(point) ?? false
        }, containsMenuPoint: { [weak self] point in
            let panel = self?.popover.contentViewController?.view.window
            return NSApp.windows.contains { window in
                window !== panel && window.isVisible && window.level >= .popUpMenu && window.frame.contains(point)
            }
        }, close: { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.popover.animates = false
            self.popover.performClose(nil)
        })
    }

    private func entryContains(_ point: CGPoint) -> Bool {
        if statusItem.button?.window?.frame.contains(point) == true { return true }
        // Mirrored native entry windows can belong to another display than
        // button.window. Inspect our own public view tree, without AX polling.
        func hasEntry(_ view: NSView) -> Bool {
            if let button = view as? NSStatusBarButton, button.toolTip == "Hasp" { return true }
            return view.subviews.contains(where: hasEntry)
        }
        return NSApp.windows.contains { window in
            window.isVisible && window.frame.contains(point) && window.contentView.map(hasEntry) == true
        }
    }

    func popoverDidClose(_ notification: Notification) {
        panelDismissMonitor.stop()
        model.panelDidClose()
        let completion = afterDismiss
        afterDismiss = nil
        completion?()
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            let window = NSWindow(contentViewController: host)
            window.title = "Hasp"
            window.identifier = NSUserInterfaceItemIdentifier("hasp.settings")
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 540))
            window.contentMinSize = NSSize(width: 520, height: 460)
            self.window = window
        }
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Explicit live verification of the same controller/model path as the switch.
/// Never called during startup, status reads, or ordinary panel presentation.
@MainActor private enum FoldPipelineProbe {
    static func run() async -> [String: Any] {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.hasp.menu")
            .allSatisfy({ $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }) else {
            return ["refused": "Quit the regular Hasp instance before this explicit probe."]
        }
        let storage = NativeMenuBarVisibilityStorage()
        let system = SystemMenuVisibility()
        guard (try? storage.journal().isEmpty) == true,
              (try? system.journal().isEmpty) == true,
              let initialData = try? storage.read(), let initial = try? MenuBarVisibilityRecords(data: initialData) else {
            return ["refused": "Native configuration is unreadable or recovery is pending."]
        }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let systemSettingsBefore = try? system.snapshot()
        let inputBefore = MenuBarCensus.currentInputIdentifier()
        var transitionPending = false
        var services = MenuBarServices.live
        let liveTransition = services.transition
        services.transition = { folded, completion in
            transitionPending = true
            liveTransition(folded) { transitionPending = false; completion() }
        }
        let model = AppModel(menuServices: services)
        let controller = MenuBarController(model: model)
        let icons = await services.snapshot()
        model.menuBarIcons = icons
        let owners = Set(icons.compactMap(\.target?.bundleIdentifier)).filter(SystemMenuVisibility.isFoldTarget)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let strips = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: 40) }
        let systemBefore = Set(MenuBarPrefs.shownSystemIcons().map(\.id))
        func settle() async -> Bool {
            let deadline = Date().addingTimeInterval(30)
            while model.menuState.layoutPending || transitionPending || model.menuBarScanPending {
                if Date() > deadline { return false }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return true
        }
        var report: [String: Any] = ["scope": "Explicit real production fold ON/OFF pipeline, no panel or input events",
                                     "targetCount": owners.count, "displayCount": strips.count]
        let start = DispatchTime.now().uptimeNanoseconds
        model.setMenuBarFolded(true)
        let folded = await settle()
        report["foldMs"] = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        report["foldCompleted"] = folded
        report["foldSwitchOn"] = model.menuBarFolded
        if let error = model.menuBarMessage { report["foldFailure"] = error }
        let hidden = await Task.detached { MenuBarCensus.nativeItemsHidden(owners: owners, strips: strips) }.value
        report["allTargetIconsHidden"] = hidden as Any? ?? "unknown"
        let restoreStart = DispatchTime.now().uptimeNanoseconds
        model.setMenuBarFolded(false)
        report["restoreCompleted"] = await settle()
        report["restoreMs"] = Double(DispatchTime.now().uptimeNanoseconds - restoreStart) / 1_000_000
        report["foldSwitchOff"] = !model.menuBarFolded
        if let error = model.menuBarMessage { report["restoreFailure"] = error }
        let restored = try? MenuBarVisibilityRecords(data: storage.read())
        report["allOriginalFlagsRestored"] = restored?.states == initial.states
        report["systemModulesRestored"] = Set(MenuBarPrefs.shownSystemIcons().map(\.id)) == systemBefore
        report["inputAndSearchPreferencesRestored"] = (try? system.snapshot()) == systemSettingsBefore
        report["currentInputSourceUnchanged"] = inputBefore != nil && MenuBarCensus.currentInputIdentifier() == inputBefore
        report["pendingSystemRestoreCount"] = (try? system.journal().count) ?? -1
        report["pendingRestoreCount"] = (try? storage.journal().count) ?? -1
        var visibleAgain = false
        for _ in 0..<30 {
            let visible = await Task.detached { MenuBarCensus.nativeRenderedOwners(strips: strips) }.value
            if let visible, owners.isSubset(of: visible) { visibleAgain = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        report["allTargetIconsVisibleAgain"] = visibleAgain
        report["panelOpened"] = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        report["foregroundStayedSame"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground
        withExtendedLifetime(controller) {}
        return report
    }
}

@main
enum HaspMain {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--diagnose-lock-screen") {
            app.setActivationPolicy(.accessory)
            let report: [String: Any] = ["available": NativeScreenLock.shared.available,
                                       "backend": "login.framework/SACLockScreenImmediate",
                                       "lockInvoked": false, "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString]
            print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
            return
        }
        if CommandLine.arguments.contains("--probe-system-menu-icons") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.hasp.menu").allSatisfy({ $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }) else { exit(2) }
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let strips = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: 40) }
                let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let report = await Task.detached { () -> [String: Any] in
                    let system = SystemMenuVisibility()
                    var report: [String: Any] = [:]
                    do {
                        guard try system.journal().isEmpty else { return ["refused": "Pending system icon recovery."] }
                        let before = try system.snapshot()
                        let owners = Set(SystemMenuVisibility.Item.allCases.map(\.owner))
                        try system.fold(owners: owners)
                        for _ in 0..<40 {
                            Thread.sleep(forTimeInterval: 0.1)
                            if let visible = MenuBarCensus.nativeRenderedOwners(strips: strips) {
                                report["remainingOwners"] = owners.intersection(visible).sorted()
                                if owners.isDisjoint(with: visible) { break }
                            }
                        }
                        try system.restore()
                        report["preferencesRestored"] = try system.snapshot() == before
                        for _ in 0..<40 {
                            Thread.sleep(forTimeInterval: 0.1)
                            if let visible = MenuBarCensus.nativeRenderedOwners(strips: strips), owners.isSubset(of: visible) { report["visibleAgain"] = true; break }
                        }
                    } catch { report["failure"] = error.localizedDescription; try? system.restore() }
                    return report
                }.value
                var output = report
                output["foregroundStayedSame"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground
                print(String(data: try! JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--probe-fold-pipeline") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                let report = await FoldPipelineProbe.run()
                let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--probe-native-fold-transport") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                let transport: NativeMenuBarVisibilityStorage.Transport = CommandLine.arguments.contains("--direct-preferences") ? .direct : (CommandLine.arguments.contains("--refresh-preferences-suite") ? .suiteRefresh : .container)
                let report = await SwitchDiagnostics.probeNativeFoldTransport(transport: transport)
                let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-permissions") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                let statuses = await NativePermissionBackend().check()
                let report = HaspPermission.allCases.map { PermissionSnapshot(permission: $0, status: statuses[$0] ?? .unknown) }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(data: try! encoder.encode(report), encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-fold-compatibility") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                let report = await SwitchDiagnostics.foldCompatibilityReport()
                let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-audio-inventory") {
            app.setActivationPolicy(.accessory)
            Task {
                let report = await SwitchDiagnostics.audioInventoryReport()
                let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-switch-performance") {
            app.setActivationPolicy(.accessory)
            Task {
                let report = await SwitchDiagnostics.readOnlyReport()
                let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
                exit(0)
            }
            app.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-menu-bar") {
            app.setActivationPolicy(.accessory)
            // Exercise the same background census path used by folding, while
            // keeping the main event loop available for input-source queries.
            Task.detached {
                let apps = MenuBarCensus.thirdPartyIcons()
                let system = MenuBarPrefs.shownSystemIcons()
                func itemReport(_ item: MenuBarIcon) -> [String: Any] {
                    var data: [String: Any] = ["id": item.id, "name": item.name, "supportsNativePress": item.target?.canPress ?? false]
                    if let status = item.status { data["status"] = status }
                    return data
                }
                let report: [String: Any] = [
                    "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                    "accessibilityTrusted": MenuBarCensus.isTrusted,
                    "icons": apps.map(itemReport),
                    "systemIcons": system.map(itemReport)
                ]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: data, encoding: .utf8) {
                    print(text)
                    exit(0)
                }
                exit(1)
            }
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController(model: model)
        if MenuBarCompatibility.policy(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) == .native27 {
            ModernMenuBarFold.shared.apply(false, icons: []) { [weak self] error in
                guard let self else { return }
                self.model.start()
                if let error {
                    self.model.menuBarFolded = error.stillFolded
                    self.model.menuState.recoveryPending = error.stillFolded
                    self.model.menuBarMessage = error.message
                }
            }
        } else { model.start() }
        if CommandLine.arguments.contains("--diagnose-menu-layout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller?.reportLayout() }
        }
        if CommandLine.arguments.contains("--open-panel") {
            controller?.showPopoverWhenReady()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { return .terminateNow }
        model.restoreMenuBarFold()
        ModernMenuBarFold.shared.apply(false, icons: []) { _ in sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27 { model.restoreMenuBarFold() }
    }
}
