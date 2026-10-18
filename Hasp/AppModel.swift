import AppKit
import Combine
import ApplicationServices
import CoreAudio
import CoreBluetooth
import CoreLocation
import Foundation
import ServiceManagement

enum BluetoothGate {
    case pending
    case asking
    case denied
    case ready
}

enum OutputKind: Equatable {
    case mac
    case wired
    case bluetooth
    case other

    var label: String {
        switch self {
        case .mac: "这台 Mac"
        case .wired: "有线"
        case .bluetooth: "蓝牙"
        case .other: ""
        }
    }

    var symbolName: String {
        switch self {
        case .mac: "laptopcomputer"
        case .wired, .bluetooth: "headphones"
        case .other: "speaker.wave.2"
        }
    }

    static func classify(name: String, transport: UInt32) -> OutputKind {
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return .bluetooth
        }
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if folded.contains("headphone") || folded.contains("headset") || folded.contains("耳机") || folded.contains("earpod") {
            return .wired
        }
        if transport == kAudioDeviceTransportTypeBuiltIn {
            return .mac
        }
        return .other
    }
}

enum AudioRowOperation: Equatable { case connecting, waitingForOutput, switching, disconnecting }
enum AudioRowFailure: Equatable { case connection, routing, disconnection }
enum AppearanceChoice: String, CaseIterable { case light = "浅色", dark = "深色", automatic = "自动" }

private struct AudioSelection: Equatable, Sendable {
    var id: String
    var uid: String
}

struct OutputItem: Identifiable, Equatable {
    var id: String
    var name: String
    var kind: OutputKind
    var isCurrent: Bool
    var pending: Bool
    var battery: String?
    var failed = false
    var pendingSelection: Bool? = nil
    var bluetoothAddress: String? = nil
    var audioUID: String? = nil
    var connected = true
    var operation: AudioRowOperation? = nil
    var failure: AudioRowFailure? = nil
    var wasOfflineAtRequest = false

    var isInPairedGroup: Bool { bluetoothAddress != nil && (!connected || (pending && wasOfflineAtRequest)) }

    var switchOn: Bool { pendingSelection ?? isCurrent }

    var symbolName: String {
        kind.symbolName
    }

    var subtitle: String {
        if let operation {
            switch operation {
            case .connecting: return "连接中…"
            case .waitingForOutput: return "已连接，正在准备声音…"
            case .switching: return "正在切换"
            case .disconnecting: return "正在断开"
            }
        }
        if let failure {
            switch failure {
            case .connection: return "连接失败，请唤醒耳机后重试"
            case .routing: return connected ? "已连接，声音切换失败，请重试" : "声音切换失败，请重试"
            case .disconnection: return "未能断开，请重试"
            }
        }
        if pending { return "正在切换" }
        if failed { return "切换失败，请重试" }
        let charge = battery.map { " · \($0)" } ?? ""
        if bluetoothAddress != nil {
            return (isCurrent ? "正在使用" : connected ? "已连接" : "未连接") + (connected ? charge : "")
        }
        if isCurrent {
            let base = kind.label.isEmpty ? "输出" : "输出 · \(kind.label)"
            return base + charge
        }
        if kind.label.isEmpty { return battery ?? "" }
        return kind.label + charge
    }

    var actionTitle: String {
        if bluetoothAddress != nil && !connected { return "连接并使用" }
        return failure == nil ? "使用" : "重试"
    }

    var kindRank: Int {
        switch kind {
        case .mac: 0
        case .wired: 1
        case .bluetooth: 2
        case .other: 3
        }
    }
}

struct DeviceItem: Identifiable, Equatable {
    var id: String { address }
    var address: String
    var name: String
    var kind: DeviceKind
    var connected: Bool
    var pending: Bool
    var failed: Bool
    var battery: String?
    var pendingConnection: Bool? = nil

    var switchOn: Bool {
        pendingConnection ?? connected
    }

    var symbolName: String { kind.symbolName }

    var subtitle: String {
        if pending { return pendingConnection == false ? "正在断开" : "正在连接" }
        if failed { return connected ? "未能断开，请重试" : "未能连接，请重试" }
        if let battery, !battery.isEmpty { return battery }
        if connected { return "已连接" }
        return ""
    }
}

@MainActor
final class AppModel: ObservableObject {
    // Stable coordinator publisher, intentionally never sent. Presentation
    // publishers live in the main-actor domain states below.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    let appearanceState = AppearanceState()
    let audioState = AudioState()
    let deviceState = DeviceState()
    let menuState = MenuBarState()
    let settingsState = SettingsState()
    let permissions = PermissionCenter()
    var isDark: Bool {
        get { appearanceState.isDark }
        set { if appearanceState.isDark != newValue { appearanceState.isDark = newValue } }
    }
    var scheduleMode: ScheduleMode {
        get { appearanceState.scheduleMode }
        set { if appearanceState.scheduleMode != newValue { appearanceState.scheduleMode = newValue } }
    }
    var customStart: Int {
        get { appearanceState.customStart }
        set { if appearanceState.customStart != newValue { appearanceState.customStart = newValue } }
    }
    var customEnd: Int {
        get { appearanceState.customEnd }
        set { if appearanceState.customEnd != newValue { appearanceState.customEnd = newValue } }
    }
    var launchAtLogin: Bool {
        get { settingsState.launchAtLogin }
        set { if settingsState.launchAtLogin != newValue { settingsState.launchAtLogin = newValue } }
    }
    var outputs: [OutputItem] {
        get { audioState.outputs }
        set { if audioState.outputs != newValue { audioState.outputs = newValue } }
    }
    var inputs: [DeviceItem] {
        get { deviceState.inputs }
        set { if deviceState.inputs != newValue { deviceState.inputs = newValue } }
    }
    var permissionMessage: String? {
        get { appearanceState.permissionMessage }
        set { if appearanceState.permissionMessage != newValue { appearanceState.permissionMessage = newValue } }
    }
    var scheduleMenuVisible: Bool {
        get { appearanceState.scheduleMenuVisible }
        set { if appearanceState.scheduleMenuVisible != newValue { appearanceState.scheduleMenuVisible = newValue } }
    }
    var menuBarFolded: Bool {
        get { menuState.folded }
        set { if menuState.folded != newValue { menuState.folded = newValue } }
    }
    var menuBarIcons: [MenuBarIcon] {
        get { menuState.icons }
        set { if menuState.icons != newValue { menuState.icons = newValue } }
    }
    var menuBarRevealed: Bool {
        get { menuState.revealed }
        set { if menuState.revealed != newValue { menuState.revealed = newValue } }
    }
    var menuBarNeedsAccess: Bool {
        get { menuState.needsAccess }
        set { if menuState.needsAccess != newValue { menuState.needsAccess = newValue } }
    }
    var menuBarMessage: String? {
        get { menuState.message }
        set { if menuState.message != newValue { menuState.message = newValue } }
    }
    var menuBarOpening: Bool {
        get { menuState.opening }
        set { if menuState.opening != newValue { menuState.opening = newValue } }
    }
    var bluetoothGate: BluetoothGate {
        get { deviceState.bluetoothGate }
        set { if deviceState.bluetoothGate != newValue { deviceState.bluetoothGate = newValue } }
    }

    let store: SettingsStore
    let bluetooth = BluetoothService()
    let ble = BLEBatteryMonitor()
    private let locationFetcher = LocationFetcher()
    private var scheduleTimer: Timer?
    private var panelVisible = false
    private var bluetoothStarted = false
    private var bluetoothStarting = false
    private var pairedNames: [(address: String, name: String)] = []
    private var hardwareBatteries: [String: String] = [:]
    private var menuBarRefreshTimer: Timer?
    private var menuBarRefreshPending = false
    private var menuBarRefreshedAt = Date.distantPast
    private var menuBarTransitionPending = false
    private var latestMenuBarItems: [String: MenuBarIcon] = [:]
    private var menuBarRevision = 0
    private var menuBarFoldRevision = 0
    private var menuBarLayoutRevision = 0
    private var menuBarInteraction: MenuBarInteraction?
    private let services: SwitchServices
    private let menuServices: MenuBarServices
    private var hardwareTask: Task<Void, Never>?
    private var hardwareDirty = false
    private var hardwareWantsBattery = false
    private var hardwareRevision = 0
    private var requestedAudio: String?
    private var disconnectTasks: [String: Task<Void, Never>] = [:]
    private var headphoneRowRevisions: [String: Int] = [:]
    private var audioIntentRevision = 0
    private var headphoneTask: Task<Void, Never>?
    private var headphoneConnections: [String: (id: UUID, connected: Bool, task: Task<Bool, Never>)] = [:]
    private var deviceCommands: [String: LatestRequest<Bool>] = [:]
    private lazy var appearanceCommands = LatestRequest<AppearanceIntent>(
        operation: { [services] intent in await SwitchTrace.operation("appearance") { await services.appearance(intent) } },
        completion: { [weak self] intent, ok in self?.appearanceCompleted(intent, ok: ok) }
    )
    private lazy var audioCommands = LatestRequest<AudioSelection>(
        operation: { [weak self] selection in
            guard let self, self.requestedAudio == selection.id else { return false }
            return await SwitchTrace.operation("audio") { await self.services.audio(selection.uid) }
        },
        completion: { [weak self] selection, ok in self?.audioCompleted(selection, ok: ok) }
    )

    init(services: SwitchServices? = nil, store: SettingsStore = SettingsStore(), menuServices: MenuBarServices = .live) {
        self.store = store
        self.services = services ?? SwitchServices.live(bluetooth: bluetooth)
        self.menuServices = menuServices
        audioState.recentHeadphoneID = store.recentHeadphoneID
    }

    var setMenuBarSpacer: ((Bool) -> Void)?
    var applyMenuBarLayout: ((Bool, @escaping (MenuBarLayoutFailure?) -> Void) -> Void)?
    var dismissPanel: ((@escaping () -> Void) -> Void)?
    var presentPanel: (() -> Void)?

    var appearanceSwitchOn: Bool {
        appearanceState.requested ?? (scheduleMode != .off || isDark)
    }

    var appearanceChoice: AppearanceChoice {
        if scheduleMode != .off { return .automatic }
        return (appearanceState.requested ?? isDark) ? .dark : .light
    }

    func selectAppearance(_ choice: AppearanceChoice) {
        if choice == .automatic {
            selectSchedule(store.automaticSchedule)
            return
        }
        let previous = scheduleMode
        if previous != .off { store.automaticSchedule = previous }
        scheduleMode = .off
        store.scheduleMode = .off
        appearanceState.requested = choice == .dark
        permissionMessage = nil
        appearanceCommands.submit(AppearanceIntent(dark: choice == .dark, fromUser: true, rollback: previous))
    }

    var appearanceSubtitle: String {
        if appearanceState.requested != nil { return "正在切换" }
        if let permissionMessage { return permissionMessage }
        switch scheduleMode {
        case .off:
            return isDark ? "深色" : "浅色"
        case .solar:
            return "日出到日落"
        case .fixed:
            return "18:00–06:00"
        case .custom:
            return Solar.formatRange(start: customStart, end: customEnd)
        }
    }

    func start() {
        MenuBarPrefs.restoreIfNeeded()
        refreshMenuBarItems()
        scheduleMode = store.scheduleMode
        customStart = store.customStart
        customEnd = store.customEnd
        launchAtLogin = store.launchAtLogin
        isDark = AppearanceService.isDark()
        // Existing permission can be reflected before first presentation.
        // Do not swap a permission placeholder for device rows mid-opening.
        switch CBCentralManager.authorization {
        case .allowedAlways: bluetoothGate = .ready
        case .denied, .restricted: bluetoothGate = .denied
        default: bluetoothGate = .pending
        }
        if launchAtLogin {
            applyLaunchAtLogin(true)
        }
        bluetooth.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                guard let self, self.bluetoothStarted else { return }
                self.requestHardwareRefresh(includeBattery: self.panelVisible)
            }
        }
        if CBCentralManager.authorization == .allowedAlways {
            // Register existing-permission notifications during startup,
            // rather than during the first popover's opening frames.
            bluetooth.start()
            bluetoothStarted = true
        }
        applyScheduleIfNeeded()
        armScheduleTimer()
        requestHardwareRefresh(includeBattery: false)
        ble.onUpdate = { [weak self] in
            Task { @MainActor in
                self?.applyKnownBatteries()
            }
        }
        AudioOutputService.startWatching { [weak self] in
            Task { @MainActor in
                self?.requestHardwareRefresh(includeBattery: false)
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isDark = AppearanceService.isDark()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyScheduleIfNeeded() }
        }
    }

    func panelDidShow() {
        // Reopening Hasp is an explicit cancellation of a pending handoff.
        // Its late callback must not close or rearrange the newly opened panel.
        if menuBarOpening || menuBarRevealed { setMenuBarFolded(menuBarFolded) }
        preparePanelPresentation()
        refreshMenuBarItems(force: false)
        menuBarRefreshTimer?.invalidate()
        menuBarRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.menuBarFolded else { return }
                // Preserve the status/notification polling cadence. The age
                // gate is for repeated opens, not for this periodic refresh.
                self.refreshMenuBarItems()
            }
        }
        requestHardwareRefresh(includeBattery: false)
        if CBCentralManager.authorization == .allowedAlways {
            ble.refresh()
        }
        beginBluetoothIfNeeded()
    }

    func preparePanelPresentation() {
        outputs = outputs.sorted(by: sortOutputs)
        inputs = inputs.sorted(by: sortDevices)
        panelVisible = true
    }

    func openBluetoothSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        NSWorkspace.shared.open(url)
    }

    private func beginBluetoothIfNeeded() {
        switch CBCentralManager.authorization {
        case .denied, .restricted:
            bluetoothGate = .denied
            return
        case .allowedAlways:
            bluetoothGate = .ready
            if bluetoothStarted {
                requestHardwareRefresh(includeBattery: true)
            } else {
                loadBluetooth()
            }
        default:
            // Permission requests belong to an explicit user action in the
            // permissions page, not to merely opening the panel.
            bluetoothGate = .pending
        }
    }

    private func loadBluetooth() {
        guard !bluetoothStarting else { return }
        bluetoothStarting = true
        let bluetooth = self.bluetooth
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = bluetooth.pairedDevices(watchDisconnects: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let denied = CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted
                self.bluetoothGate = denied ? .denied : .ready
                if !denied {
                    bluetooth.start()
                    self.bluetoothStarted = true
                    self.requestHardwareRefresh(includeBattery: self.panelVisible)
                    if self.panelVisible {
                        self.ble.refresh()
                    }
                }
                self.bluetoothStarting = false
            }
        }
    }

    func panelDidClose() {
        panelVisible = false
        scheduleMenuVisible = false
        menuBarRefreshTimer?.invalidate()
        menuBarRefreshTimer = nil
    }

    func setMenuBarFolded(_ on: Bool) {
        SwitchTrace.intent("fold")
        menuBarRevision += 1
        menuBarFoldRevision += 1
        menuBarInteraction?.cancel()
        menuBarInteraction = nil
        accessTimer?.invalidate()
        menuBarRevealed = false
        menuBarOpening = false
        menuBarMessage = nil
        menuBarFolded = on
        if on {
            menuBarNeedsAccess = !menuServices.isTrusted()
            if menuBarNeedsAccess {
                menuBarFolded = false
                menuBarMessage = "需要辅助功能权限。请打开「设置 → 权限」启用辅助功能后重试。"
                return
            }
        } else {
            menuBarNeedsAccess = false
        }
        // The modern backend owns the entire prepared batch and its rollback.
        let revision = menuBarFoldRevision
        let transition = { [weak self] in
            guard let self, revision == self.menuBarFoldRevision else { return }
            self.menuBarTransitionPending = true
            self.menuServices.transition(on) { [weak self] in
                guard let self, revision == self.menuBarFoldRevision else { return }
                self.menuBarTransitionPending = false
                // Keep complete AX handles and rows warm across a visibility
                // toggle. Ordinary panel/timer refreshes reconcile app changes.
                if self.menuServices.refreshesAfterTransition || self.menuBarIcons.isEmpty {
                    self.refreshMenuBarItems()
                }
            }
        }
        if menuServices.waitsForLayout {
            requestMenuBarLayout(on) { ok in if ok { transition() } }
        } else {
            requestMenuBarLayout(on)
            transition()
        }
    }

    private func requestMenuBarLayout(_ on: Bool, showPending: Bool = true, completed: @escaping (Bool) -> Void = { _ in }) {
        guard let applyMenuBarLayout else { setMenuBarSpacer?(on); completed(true); return }
        let revision = menuBarFoldRevision
        menuBarLayoutRevision += 1
        let layoutRevision = menuBarLayoutRevision
        if showPending { menuState.layoutPending = true }
        applyMenuBarLayout(on) { [weak self] error in
            guard let self, revision == self.menuBarFoldRevision, layoutRevision == self.menuBarLayoutRevision else { return }
            self.menuState.layoutPending = false
            guard let error else { self.menuState.recoveryPending = false; completed(true); return }
            self.menuBarRevision += 1
            self.menuBarFoldRevision += 1
            self.menuBarInteraction?.cancel()
            self.menuBarInteraction = nil
            self.menuBarFolded = error.stillFolded
            self.menuState.recoveryPending = error.stillFolded
            self.menuBarRevealed = false
            self.menuBarOpening = false
            self.menuBarNeedsAccess = false
            self.menuBarMessage = error.message
            self.menuBarTransitionPending = true
            let rollback = self.menuBarFoldRevision
            self.menuServices.transition(error.stillFolded) { [weak self] in
                guard let self, rollback == self.menuBarFoldRevision else { return }
                self.menuBarTransitionPending = false
                self.refreshMenuBarItems()
            }
            completed(false)
        }
    }

    // Warm the same complete cache even while unfolded. Opening/folding only
    // reveals that cache; a refresh never replaces it with system-only rows.
    var menuBarScanPending: Bool { menuBarRefreshPending }

    func refreshMenuBarItems(force: Bool = true) {
        guard !menuBarTransitionPending, !menuState.layoutPending, !menuBarOpening, !menuBarRevealed,
              !menuBarRefreshPending else { return }
        if !force && Date().timeIntervalSince(menuBarRefreshedAt) < 2 { return }
        menuBarRefreshPending = true
        // A spinner is only useful for a cold list. Publishing it on every
        // warm refresh invalidates the menu section twice for no visible gain.
        if menuBarIcons.isEmpty && !menuState.refreshing { menuState.refreshing = true }
        let revision = menuBarRevision
        Task { [weak self, menuServices] in
            let icons = await menuServices.snapshot()
            self?.applyMenuBarSnapshot(icons, revision: revision)
        }
    }

    private func applyMenuBarSnapshot(_ icons: [MenuBarIcon], revision: Int) {
        menuBarRefreshPending = false
        if menuState.refreshing { menuState.refreshing = false }
        guard revision == menuBarRevision else { refreshMenuBarItems(); return }
        menuBarRefreshedAt = Date()
        let previousIDs = Set(menuBarIcons.map(\.id))
        latestMenuBarItems = Dictionary(uniqueKeysWithValues: icons.map { ($0.id, $0) })
        // Keep fresh AX handles without invalidating the whole glass panel
        // every two seconds when names/status have not actually changed.
        if menuBarIcons != icons { menuBarIcons = icons }
        let needsAccess = menuBarFolded && !menuServices.isTrusted()
        if menuBarNeedsAccess != needsAccess { menuBarNeedsAccess = needsAccess }
        if menuServices.waitsForLayout, menuBarFolded, !needsAccess,
           icons.contains(where: { !$0.id.hasPrefix("system.") && !previousIDs.contains($0.id) }) {
            requestMenuBarLayout(true, showPending: false)
        }
    }

    func openMenuBarItem(_ icon: MenuBarIcon) {
        guard menuBarFolded, !menuBarOpening, !menuState.layoutPending, !menuState.recoveryPending else { return }
        let icon = latestMenuBarItems[icon.id] ?? icon
        menuBarRevision += 1
        let revision = menuBarRevision
        menuBarInteraction?.cancel()
        menuBarInteraction = nil
        menuBarOpening = true
        menuBarMessage = nil
        let begin = { [weak self] in self?.beginMenuBarHandoff(icon, revision: revision) }
        // Wait for the glass panel's dismissal before changing menu-bar layout.
        if let dismissPanel { dismissPanel { begin() } } else { begin() }
    }

    private func beginMenuBarHandoff(_ icon: MenuBarIcon, revision: Int) {
        guard revision == menuBarRevision, menuBarFolded else { return }
        menuBarRevealed = true
        requestMenuBarLayout(false) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.presentPanel?(); return }
            guard revision == self.menuBarRevision, self.menuBarFolded else { return }
            self.menuServices.transition(false) { [weak self] in
                guard let self, revision == self.menuBarRevision, self.menuBarFolded else { return }
                self.resolveMenuBarHandoff(icon, revision: revision)
            }
        }
    }

    private func resolveMenuBarHandoff(_ icon: MenuBarIcon, revision: Int) {
        Task { [weak self] in
            // Wait for Control Center to recreate system items and for AppKit
            // to lay out restored third-party items before issuing AXPress.
            var target: MenuBarTarget?
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, revision == self.menuBarRevision, self.menuBarFolded else { return }
                let resolved = await Task.detached { () -> (MenuBarTarget, CGRect)? in
                    guard let candidate = MenuBarCensus.target(for: icon), candidate.canPress,
                          let value = MenuBarCensus.attribute(candidate.element, "AXFrame"),
                          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
                    var rect = CGRect.zero
                    guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgRect, &rect) else { return nil }
                    return (candidate, rect)
                }.value
                if let (candidate, rect) = resolved {
                    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
                    let visible = NSScreen.screens.contains { screen in
                        let frame = screen.frame
                        let quartzFrame = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
                        return quartzFrame.intersects(rect)
                    }
                    if rect.width > 0 && visible { target = candidate; break }
                }
            }
            guard let self, revision == self.menuBarRevision, self.menuBarFolded else { return }
            self.menuBarOpening = false
            guard let target else {
                self.finishMenuBarInteraction("这个项目未提供可用的原菜单入口，可用折叠开关展开后直接点击原图标。")
                return
            }
            let session = MenuBarInteraction(target: target) { [weak self] message in
                guard let self, revision == self.menuBarRevision else { return }
                self.finishMenuBarInteraction(message)
            }
            self.menuBarInteraction = session
            session.start()
        }
    }

    private func finishMenuBarInteraction(_ message: String?) {
        menuBarInteraction?.cancel()
        menuBarInteraction = nil
        menuBarOpening = false
        menuBarRevealed = false
        menuBarMessage = message
        if menuBarFolded {
            let revision = menuBarRevision
            requestMenuBarLayout(true) { [weak self] ok in
                guard let self, ok, revision == self.menuBarRevision, self.menuBarFolded else { return }
                self.menuServices.transition(true) { [weak self] in
                    guard let self, revision == self.menuBarRevision else { return }
                    if message != nil { self.presentPanel?() }
                }
            }
        } else if message != nil {
            presentPanel?()
        }
    }

    func openMenuBarApplication(_ icon: MenuBarIcon) {
        let icon = latestMenuBarItems[icon.id] ?? icon
        guard let target = icon.target,
              let app = NSRunningApplication(processIdentifier: target.pid),
              let url = MenuBarCensus.ownerApplicationURL(app) else { return }
        if menuBarRevealed { finishMenuBarInteraction(nil) }
        // This secondary action is explicitly selected by the user.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let open = { NSWorkspace.shared.openApplication(at: url, configuration: configuration) }
        if let dismissPanel { dismissPanel { open() } } else { open() }
    }

    func restoreMenuBarFold() {
        menuBarRevision += 1
        menuBarFoldRevision += 1
        menuBarTransitionPending = false
        menuBarInteraction?.cancel()
        menuBarInteraction = nil
        menuBarRefreshTimer?.invalidate()
        accessTimer?.invalidate()
        menuBarFolded = false
        menuBarRevealed = false
        menuBarOpening = false
        menuBarNeedsAccess = false
        menuBarIcons = []
        requestMenuBarLayout(false)
        MenuBarPrefs.show()
    }

    private var accessTimer: Timer?

    private func watchMenuBarAccess() {
        accessTimer?.invalidate()
        var tries = 0
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            tries += 1
            let trusted = MenuBarCensus.isTrusted
            if trusted {
                Task { @MainActor in
                    guard let self, self.menuBarFolded else { return }
                    self.refreshMenuBarItems()
                    self.menuBarNeedsAccess = false
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            if trusted || tries > 20 { timer.invalidate() }
        }
    }

    func setAppearanceSwitch(_ on: Bool) {
        SwitchTrace.intent("appearance")
        let previous = scheduleMode
        if !on { scheduleMode = .off; store.scheduleMode = .off }
        appearanceState.requested = on
        permissionMessage = nil
        appearanceCommands.submit(AppearanceIntent(dark: on, fromUser: true, rollback: on ? nil : previous))
        SwitchTrace.applied("appearance-intent")
    }

    private func appearanceCompleted(_ intent: AppearanceIntent, ok: Bool) {
        appearanceState.requested = nil
        if ok {
            isDark = intent.dark
            permissionMessage = nil
        } else {
            if let previous = intent.rollback, scheduleMode == .off {
                scheduleMode = previous
                store.scheduleMode = previous
            }
            permissionMessage = AppearanceService.permissionSubtitle
        }
        SwitchTrace.applied("appearance-result")
    }

    func selectSchedule(_ mode: ScheduleMode) {
        scheduleMode = mode
        store.scheduleMode = mode
        store.automaticSchedule = mode
        permissionMessage = nil
        if mode == .solar {
            prepareSolarCoordinate()
        }
        applyScheduleIfNeeded()
        scheduleMenuVisible = false
    }

    func setCustomStart(_ minutes: Int) {
        customStart = minutes
        store.customStart = minutes
        if scheduleMode == .custom { applyScheduleIfNeeded() }
    }

    func setCustomEnd(_ minutes: Int) {
        customEnd = minutes
        store.customEnd = minutes
        if scheduleMode == .custom { applyScheduleIfNeeded() }
    }

    func setLaunchAtLogin(_ on: Bool) {
        store.launchAtLogin = on
        applyLaunchAtLogin(on)
    }

    func selectOutput(_ item: OutputItem, on: Bool) {
        guard let current = outputs.first(where: { $0.id == item.id }) else { return }
        let target: OutputItem
        if on {
            guard !current.switchOn || current.failure != nil || current.operation == .disconnecting else { return }
            target = current
        } else {
            guard current.switchOn,
                  let fallback = outputs.first(where: { $0.kind == .mac && $0.id != current.id })
                    ?? outputs.first(where: { $0.id != current.id }) else { return }
            target = fallback
        }
        SwitchTrace.intent("audio")
        beginAudioIntent(id: target.id)
        headphoneRowRevisions[target.id, default: 0] += 1
        let revision = audioIntentRevision
        updateOutput(target.id) {
            $0.wasOfflineAtRequest = target.isInPairedGroup
            $0.operation = target.bluetoothAddress != nil && !target.connected ? .connecting : .switching
        }
        guard let address = target.bluetoothAddress else {
            audioCommands.submit(AudioSelection(id: target.id, uid: target.audioUID ?? target.id))
            SwitchTrace.applied("audio-intent")
            return
        }
        // Connection may be slow. Keep it off the audio-selection queue so a
        // later click on Mac speakers can take effect without waiting for it.
        headphoneTask = Task { [weak self] in
            guard let self else { return }
            // A previous explicit disconnect may still be finishing even if
            // the latest snapshot says connected. Queue the new connect after it.
            let needsConnection = !target.connected || self.headphoneConnections[AudioOutputInventory.addressKey(address)] != nil
            if needsConnection { self.updateOutput(target.id) { $0.operation = .connecting } }
            let connected = needsConnection ? await self.headphoneConnection(address, connected: true) : true
            guard self.audioIntentRevision == revision, !Task.isCancelled else { return }
            self.hardwareRevision += 1
            guard connected else {
                self.audioPreparationFailed(id: target.id, failure: .connection)
                return
            }
            self.updateOutput(target.id) { $0.connected = true; $0.operation = .waitingForOutput }
            let deadline = Date().addingTimeInterval(self.services.audioReadyTimeout)
            repeat {
                let available = await self.services.availableOutputs()
                guard self.audioIntentRevision == revision, !Task.isCancelled else { return }
                if let endpoint = AudioOutputInventory.endpoint(for: address, in: available) {
                    self.updateOutput(target.id) { $0.audioUID = endpoint.uid; $0.operation = .switching }
                    self.audioCommands.submit(AudioSelection(id: target.id, uid: endpoint.uid))
                    self.headphoneTask = nil
                    return
                }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            } while Date() < deadline
            guard self.audioIntentRevision == revision, !Task.isCancelled else { return }
            self.audioPreparationFailed(id: target.id, failure: .routing)
        }
        SwitchTrace.applied("audio-intent")
    }

    private func beginAudioIntent(id: String) {
        audioIntentRevision += 1
        headphoneTask?.cancel()
        headphoneTask = nil
        hardwareRevision += 1
        requestedAudio = id
        var next = outputs
        for index in next.indices {
            next[index].pending = next[index].id == id || disconnectTasks[next[index].id] != nil
            next[index].pendingSelection = next[index].id == id
            if next[index].operation != .disconnecting { next[index].operation = nil }
            if next[index].id == id { next[index].failed = false; next[index].failure = nil }
        }
        outputs = next
    }

    /// Serialize opposite connection intents for the same address. A superseded
    /// route can finish connecting, but must never select its late audio output.
    private func headphoneConnection(_ address: String, connected: Bool) async -> Bool {
        let key = AudioOutputInventory.addressKey(address)
        if let job = headphoneConnections[key], job.connected == connected { return await job.task.value }
        let previous = headphoneConnections[key]?.task
        let id = UUID()
        let task = Task { [services] in
            if let previous { _ = await previous.value }
            return await services.device(address, connected)
        }
        headphoneConnections[key] = (id, connected, task)
        let ok = await task.value
        if headphoneConnections[key]?.id == id { headphoneConnections.removeValue(forKey: key) }
        return ok
    }

    func disconnectOutput(_ item: OutputItem) {
        guard let current = outputs.first(where: { $0.id == item.id }),
              let address = current.bluetoothAddress, current.connected, !current.pending else { return }
        hardwareRevision += 1
        headphoneRowRevisions[current.id, default: 0] += 1
        let revision = headphoneRowRevisions[current.id]!
        updateOutput(current.id) { $0.pending = true; $0.operation = .disconnecting; $0.failure = nil; $0.failed = false }
        disconnectTasks[current.id] = Task { [weak self] in
            guard let self else { return }
            let ok = await self.headphoneConnection(address, connected: false)
            self.hardwareRevision += 1
            self.disconnectTasks.removeValue(forKey: current.id)
            if self.headphoneRowRevisions[current.id] == revision {
                self.updateOutput(current.id) {
                    $0.pending = false; $0.operation = nil; $0.pendingSelection = nil
                    $0.failure = ok ? nil : .disconnection
                    if ok { $0.connected = false; $0.isCurrent = false; $0.audioUID = nil; $0.battery = nil }
                }
            }
            self.requestHardwareRefresh(includeBattery: false)
        }
    }

    func activateOutput(_ item: OutputItem) {
        if item.failure == .disconnection { disconnectOutput(item) }
        else { selectOutput(item, on: true) }
    }

    private func audioPreparationFailed(id: String, failure: AudioRowFailure) {
        hardwareRevision += 1
        requestedAudio = nil
        headphoneTask = nil
        var next = outputs
        for index in next.indices {
            next[index].pending = disconnectTasks[next[index].id] != nil
            next[index].pendingSelection = nil
            if !next[index].pending { next[index].operation = nil }
            if next[index].id == id { next[index].failure = failure }
        }
        outputs = next
        requestHardwareRefresh(includeBattery: false)
    }

    private func updateOutput(_ id: String, _ change: (inout OutputItem) -> Void) {
        var next = outputs
        if let index = next.firstIndex(where: { $0.id == id }) { change(&next[index]) }
        outputs = next
    }

    private func audioCompleted(_ selection: AudioSelection, ok: Bool) {
        guard requestedAudio == selection.id else { return }
        hardwareRevision += 1
        requestedAudio = nil
        var next = outputs
        for index in next.indices {
            next[index].pending = disconnectTasks[next[index].id] != nil
            next[index].pendingSelection = nil
            if !next[index].pending { next[index].operation = nil }
            if ok { next[index].isCurrent = next[index].id == selection.id }
            if next[index].id == selection.id {
                next[index].failed = !ok
                next[index].failure = !ok && next[index].bluetoothAddress != nil ? .routing : nil
            }
        }
        outputs = next
        if ok, next.contains(where: { $0.id == selection.id && $0.bluetoothAddress != nil }) {
            store.recentHeadphoneID = selection.id
            audioState.recentHeadphoneID = selection.id
        }
        requestHardwareRefresh(includeBattery: false)
        SwitchTrace.applied("audio-result")
    }

    func toggleDevice(_ item: DeviceItem, on: Bool) {
        guard let current = inputs.first(where: { $0.address == item.address }), current.switchOn != on else { return }
        SwitchTrace.intent("bluetooth")
        hardwareRevision += 1
        update(address: item.address) { device in
            device.pending = true
            device.pendingConnection = on
            device.failed = false
        }
        let address = item.address
        if deviceCommands[address] == nil {
            deviceCommands[address] = LatestRequest<Bool>(
                operation: { [services] connected in
                    await SwitchTrace.operation("bluetooth") { await services.device(address, connected) }
                },
                completion: { [weak self] connected, ok in
                    guard let self else { return }
                    self.hardwareRevision += 1
                    self.update(address: address) { device in
                        device.pending = false
                        device.pendingConnection = nil
                        device.failed = !ok
                        if ok { device.connected = connected }
                    }
                    self.requestHardwareRefresh(includeBattery: self.panelVisible)
                    SwitchTrace.applied("bluetooth-result")
                }
            )
        }
        deviceCommands[address]?.submit(on)
        SwitchTrace.applied("bluetooth-intent")
    }

    func openSettings() {
        if let dismissPanel { dismissPanel { SettingsWindow.show(model: self) } }
        else { SettingsWindow.show(model: self) }
    }

    func openPermissions() {
        settingsState.selectedTab = .permissions
        openSettings()
    }

    private func prepareSolarCoordinate() {
        if store.latitude != nil, store.longitude != nil, !store.locationIsEstimate { return }
        if store.didAskLocation, store.latitude != nil { return }
        store.didAskLocation = true
        NSApp.activate()
        locationFetcher.request { [weak self] location in
            Task { @MainActor in
                guard let self else { return }
                if let location {
                    self.store.latitude = location.coordinate.latitude
                    self.store.longitude = location.coordinate.longitude
                    self.store.locationIsEstimate = false
                } else {
                    let estimate = TimeZoneEstimate.coordinate()
                    self.store.latitude = estimate.latitude
                    self.store.longitude = estimate.longitude
                    self.store.locationIsEstimate = true
                }
                self.applyScheduleIfNeeded()
            }
        }
    }

    private func coordinate() -> (Double, Double) {
        if let latitude = store.latitude, let longitude = store.longitude {
            return (latitude, longitude)
        }
        return TimeZoneEstimate.coordinate()
    }

    private func applyScheduleIfNeeded() {
        guard scheduleMode != .off else { return }
        let place = coordinate()
        let shouldBeDark = Solar.isDark(
            at: Date(),
            mode: scheduleMode,
            customStart: customStart,
            customEnd: customEnd,
            latitude: place.0,
            longitude: place.1,
            timeZone: .current
        )
        guard appearanceState.requested != shouldBeDark else { return }
        guard appearanceState.requested != nil || shouldBeDark != isDark else { return }
        appearanceState.requested = shouldBeDark
        appearanceCommands.submit(AppearanceIntent(dark: shouldBeDark, fromUser: false))
    }

    private func armScheduleTimer() {
        scheduleTimer?.invalidate()
        let delay = 60 - (Int(Date().timeIntervalSince1970) % 60)
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(delay, 1)), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.applyScheduleIfNeeded()
                self?.scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.applyScheduleIfNeeded() }
                }
            }
        }
    }

    func requestHardwareRefresh(includeBattery: Bool) {
        hardwareDirty = true
        hardwareWantsBattery = hardwareWantsBattery || includeBattery
        guard hardwareTask == nil else { return }
        hardwareTask = Task { [weak self] in
            // A short coalescing window absorbs command completion + system
            // notification bursts. Presentation updates are already immediate.
            try? await Task.sleep(for: .milliseconds(30))
            guard let self else { return }
            while self.hardwareDirty {
                self.hardwareDirty = false
                let battery = self.hardwareWantsBattery
                self.hardwareWantsBattery = false
                let revision = self.hardwareRevision
                let snapshot = await SwitchTrace.operation("hardware-refresh") { await self.services.snapshot(battery) }
                if revision == self.hardwareRevision {
                    self.applyHardwareSnapshot(snapshot)
                } else {
                    self.hardwareDirty = true
                    self.hardwareWantsBattery = self.hardwareWantsBattery || battery
                }
            }
            self.hardwareTask = nil
        }
    }

    func finishHardwareRefresh() async { await hardwareTask?.value }

    private func applyHardwareSnapshot(_ snapshot: HardwareSnapshot) {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { SwitchTrace.duration("hardware-apply", since: start) }
        pairedNames = snapshot.devices.map { ($0.address, $0.name) }
        hardwareBatteries = snapshot.batteries
        let inventory = AudioOutputInventory.items(snapshot)
        if audioState.recentHeadphoneID == nil,
           let active = inventory.first(where: { $0.isCurrent && $0.bluetoothAddress != nil }) {
            audioState.recentHeadphoneID = active.id
            store.recentHeadphoneID = active.id
        }
        let audioAddresses = Set(inventory.compactMap(\.bluetoothAddress).map(AudioOutputInventory.addressKey))
        let previousInputs = Dictionary(uniqueKeysWithValues: inputs.map { ($0.address, $0) })
        let nextInputs = snapshot.devices.filter { !audioAddresses.contains(AudioOutputInventory.addressKey($0.address)) }.map { device in
            let prior = previousInputs[device.address]
            return DeviceItem(address: device.address, name: device.name, kind: device.kind,
                connected: device.connected, pending: prior?.pending ?? false,
                failed: prior?.connected == device.connected && prior?.failed == true,
                battery: batteryLabel(name: device.name, address: device.address) ?? prior?.battery,
                pendingConnection: prior?.pendingConnection)
        }.sorted(by: sortDevices)
        inputs = StableRows.ordered(nextInputs, previous: inputs, preserve: panelVisible)
        if bluetoothStarted { bluetooth.watchDevices(addresses: snapshot.devices.map(\.address)) }
        let previousOutputs = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, $0) })
        let nextOutputs = inventory.map { item in
            var next = item
            let prior = previousOutputs[item.id]
            next.pending = requestedAudio == item.id || disconnectTasks[item.id] != nil
            next.operation = next.pending ? prior?.operation : nil
            next.wasOfflineAtRequest = next.pending && prior?.wasOfflineAtRequest == true
            next.pendingSelection = requestedAudio.map { $0 == item.id }
            next.failed = !item.isCurrent && prior?.failed == true
            if let failure = prior?.failure {
                let resolved = (failure == .connection && item.connected) ||
                    (failure == .routing && item.isCurrent) ||
                    (failure == .disconnection && !item.connected)
                next.failure = resolved ? nil : failure
            }
            if item.kind == .bluetooth && item.connected {
                next.battery = batteryLabel(name: item.name, address: item.bluetoothAddress)
            }
            return next
        }.sorted(by: sortOutputs)
        outputs = StableRows.ordered(nextOutputs, previous: outputs, preserve: panelVisible)
        SwitchTrace.applied("hardware-snapshot")
    }

    private func applyKnownBatteries() {
        var nextInputs = inputs
        for index in nextInputs.indices {
            if let label = batteryLabel(name: nextInputs[index].name, address: nextInputs[index].address) {
                nextInputs[index].battery = label
            }
        }
        inputs = nextInputs
        var nextOutputs = outputs
        for index in nextOutputs.indices where nextOutputs[index].kind == .bluetooth && nextOutputs[index].connected {
            if let label = batteryLabel(name: nextOutputs[index].name, address: nextOutputs[index].bluetoothAddress) { nextOutputs[index].battery = label }
        }
        outputs = nextOutputs
    }

    private func sortOutputs(_ lhs: OutputItem, _ rhs: OutputItem) -> Bool {
        if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent && !rhs.isCurrent }
        if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func batteryLabel(name: String, address: String?) -> String? {
        if let address {
            if let label = hardwareBatteries[address] { return label }
            // A BLE name is only a safe fallback when it identifies one device.
            guard pairedNames.filter({ namesMatch($0.name, name) }).count == 1 else { return nil }
            return ble.level(named: name)
        }
        if let match = pairedNames.first(where: { namesMatch($0.name, name) }),
           let label = hardwareBatteries[match.address] {
            return label
        }
        if let label = ble.level(named: name) { return label }
        if let match = pairedNames.first(where: { namesMatch($0.name, name) }),
           let label = ble.level(named: match.name) {
            return label
        }
        return nil
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let right = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return left == right || left.contains(right) || right.contains(left)
    }

    private func sortDevices(_ lhs: DeviceItem, _ rhs: DeviceItem) -> Bool {
        if lhs.connected != rhs.connected { return lhs.connected && !rhs.connected }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func update(address: String, _ change: (inout DeviceItem) -> Void) {
        if let index = inputs.firstIndex(where: { $0.address == address }) {
            change(&inputs[index])
        }
    }

    private func applyLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

}

final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?

    func request(_ completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        manager.delegate = self
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        let completion = completion
        self.completion = nil
        completion?(location)
    }
}
