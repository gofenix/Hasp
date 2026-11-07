import AppKit
import ApplicationServices
import Carbon
import Observation
import CoreBluetooth
import CoreLocation

enum HaspPermission: String, CaseIterable, Identifiable, Codable {
    case accessibility, automation, bluetooth, location, menuConfiguration
    var id: String { rawValue }
    static var usedPermissions: [Self] {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 ? allCases : allCases.filter { $0 != .menuConfiguration }
    }
    var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .automation: return "自动化 · System Events"
        case .bluetooth: return "蓝牙"
        case .location: return "定位服务"
        case .menuConfiguration: return "菜单栏配置访问"
        }
    }
    var detail: String {
        switch self {
        case .accessibility: return "读取状态栏应用并打开其原生菜单。"
        case .automation: return "通过 System Events 切换系统外观。"
        case .bluetooth: return "显示已配对设备，连接或断开耳机。"
        case .location: return "可选 · 按所在地日出日落切换外观。固定时段无需定位。"
        case .menuConfiguration: return "用于 macOS 27 状态栏折叠。外观、声音和蓝牙功能无需此访问。"
        }
    }
    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .automation: return "gearshape.2"
        case .bluetooth: return "headphones"
        case .location: return "location"
        case .menuConfiguration: return "menubar.rectangle"
        }
    }
    var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .automation: return "Privacy_Automation"
        case .bluetooth: return "Privacy_Bluetooth"
        case .location: return "Privacy_LocationServices"
        case .menuConfiguration: return "Privacy_AllFiles"
        }
    }
    var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(settingsAnchor)")!
    }
}

enum PermissionStatus: String, Codable {
    case checking, authorized, notRequested, denied, restricted, unavailable, unknown, readable
    var label: String {
        switch self {
        case .checking: return "检查中"
        case .authorized: return "已授权"
        case .notRequested: return "尚未申请"
        case .denied: return "未授权"
        case .restricted: return "系统限制"
        case .unavailable: return "服务已关闭"
        case .unknown: return "未能确认"
        case .readable: return "配置可读取"
        }
    }
    var granted: Bool { self == .authorized || self == .readable }
    func action(for permission: HaspPermission) -> String? {
        guard !granted, self != .checking else { return nil }
        if self == .notRequested, permission != .menuConfiguration { return "申请授权" }
        if self == .unknown, permission == .automation { return "申请授权" }
        return "打开设置"
    }
}

struct PermissionSnapshot: Codable {
    let permission: HaspPermission
    let status: PermissionStatus
}

/// Check and request are deliberately separate: opening a view must never ask
/// for consent, open Settings, or activate an application.
@MainActor protocol PermissionBackend: AnyObject {
    func check() async -> [HaspPermission: PermissionStatus]
    /// nil means the request was sent, not that consent was granted.
    func request(_ permission: HaspPermission) async -> String?
    func openSettings(_ permission: HaspPermission) -> Bool
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
}

extension PermissionBackend {
    func observeChanges(_ handler: @escaping @MainActor () -> Void) {}
}

@MainActor @Observable final class PermissionCenter {
    private(set) var statuses: [HaspPermission: PermissionStatus] = [:]
    private(set) var refreshing = false
    private(set) var pending: Set<HaspPermission> = []
    private(set) var feedback: [HaspPermission: String] = [:]
    var requesting: HaspPermission? { HaspPermission.allCases.first(where: pending.contains) }
    var message: String? { HaspPermission.allCases.compactMap { feedback[$0] }.first }
    private let backend: PermissionBackend
    private struct Check {
        let id = UUID()
        let revision: Int
        let task: Task<[HaspPermission: PermissionStatus], Never>
    }
    private var check: Check?
    private var revision = 0
    init(backend: PermissionBackend? = nil) {
        self.backend = backend ?? NativePermissionBackend()
        self.backend.observeChanges { [weak self] in
            Task { await self?.refreshAfterChange() }
        }
    }
    func status(_ permission: HaspPermission) -> PermissionStatus { statuses[permission] ?? .checking }

    func refreshAfterChange() async {
        revision += 1
        await refresh(minimumRevision: revision)
    }

    /// Passive checks preserve button availability and publish only changes.
    /// Manual progress is separate from the single shared background read.
    func refresh(manual: Bool = false, minimumRevision: Int = 0) async {
        if manual {
            guard !refreshing else { return }
            refreshing = true
        }
        defer { if manual { refreshing = false } }
        while let old = check, old.revision < minimumRevision { await finish(old) }
        let job: Check
        if let current = check { job = current }
        else {
            job = Check(revision: revision, task: Task { await backend.check() })
            check = job
        }
        await finish(job)
    }

    private func finish(_ job: Check) async {
        let result = await job.task.value
        guard check?.id == job.id else { return }
        check = nil
        guard job.revision == revision else { return } // A request invalidated this read.
        if statuses != result { statuses = result }
        let next = feedback.filter { !(result[$0.key]?.granted ?? false) }
        if next != feedback { feedback = next }
    }

    func performAction(_ permission: HaspPermission) async {
        guard !pending.contains(permission) else { return }
        let current = status(permission)
        guard let action = current.action(for: permission) else { return }
        pending.insert(permission)
        revision += 1
        feedback[permission] = "正在向系统发送请求…"
        if action == "申请授权" {
            let error = await backend.request(permission)
            feedback[permission] = error ?? "已向系统请求授权。若没有出现提示，可打开设置查看。"
        } else {
            openSettings(permission)
        }
        revision += 1
        // Wait out an older read and request a fresh result. The click itself
        // is delivered immediately even when a background check is slow.
        await refresh(minimumRevision: revision)
        pending.remove(permission)
    }

    func openSettings(_ permission: HaspPermission) {
        feedback[permission] = backend.openSettings(permission)
            ? "已向系统设置发送打开请求。请在对应页面启用 Hasp，返回后会重新检查。"
            : "未能打开系统设置。请手动前往「隐私与安全性」中的对应权限页面。"
    }
}

@MainActor final class NativePermissionBackend: NSObject, PermissionBackend, CBCentralManagerDelegate, CLLocationManagerDelegate {
    private var bluetoothManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private var authorizationChanged: (@MainActor () -> Void)?

    func observeChanges(_ handler: @escaping @MainActor () -> Void) { authorizationChanged = handler }

    func check() async -> [HaspPermission: PermissionStatus] {
        var result = await Task.detached(priority: .utility) {
            [HaspPermission.accessibility: AXIsProcessTrusted() ? PermissionStatus.authorized : .denied,
             .automation: Self.automationStatus(AppearanceService.permissionStatus()),
             .menuConfiguration: Self.configurationAccess()]
        }.value
        switch CBCentralManager.authorization {
        case .allowedAlways: result[.bluetooth] = .authorized
        case .notDetermined: result[.bluetooth] = .notRequested
        case .restricted: result[.bluetooth] = .restricted
        case .denied: result[.bluetooth] = .denied
        @unknown default: result[.bluetooth] = .unknown
        }
        // A manager without start/request calls only inspects authorization.
        let manager = locationManager ?? CLLocationManager()
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways: result[.location] = .authorized
        case .notDetermined: result[.location] = .notRequested
        case .restricted: result[.location] = .restricted
        case .denied: result[.location] = .denied
        @unknown default: result[.location] = .unknown
        }
        return result
    }

    nonisolated static func automationStatus(_ code: OSStatus) -> PermissionStatus {
        switch code {
        case noErr: return .authorized
        case -1744: return .notRequested // errAEEventWouldRequireUserConsent
        case -1743: return .denied // errAEEventNotPermitted
        default: return .unknown // Includes a target which is not running.
        }
    }

    nonisolated static func configurationAccess(at url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist")) -> PermissionStatus {
        // Probe only the configuration needed for compatibility investigation.
        // Do not touch the TCC database, and do not infer full-disk consent from
        // a missing/invalid file or label this capability check "authorized".
        do {
            let data = try Data(contentsOf: url)
            guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else { return .unknown }
            return .readable
        } catch {
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return .denied }
            if [error, underlying].compactMap({ $0 }).contains(where: {
                $0.domain == NSPOSIXErrorDomain && ($0.code == Int(EACCES) || $0.code == Int(EPERM))
            }) { return .denied }
            return .unknown
        }
    }

    func request(_ permission: HaspPermission) async -> String? {
        switch permission {
        case .accessibility:
            // Currently the dashboard routes AX to Settings; keep prompting
            // explicit if a future native status gains notDetermined support.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return nil
        case .automation:
            guard await AppearanceService.ensureTargetRunning() else { return "无法启动 System Events，请打开自动化设置检查。" }
            let code = await Task.detached { AppearanceService.requestPermission() }.value
            return Self.automationRequestError(code)
        case .bluetooth:
            bluetoothManager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            return nil
        case .location:
            guard await Task.detached(operation: { CLLocationManager.locationServicesEnabled() }).value else {
                return "系统定位服务已关闭，请在定位服务设置中开启。"
            }
            let manager = CLLocationManager()
            manager.delegate = self
            locationManager = manager
            manager.requestWhenInUseAuthorization()
            return nil
        case .menuConfiguration: return openSettings(permission) ? nil : "未能打开完整磁盘访问设置。"
        }
    }

    nonisolated static func automationRequestError(_ code: OSStatus) -> String? {
        switch code {
        case noErr, -1744: return nil
        case -1743: return "系统未允许自动化请求。请打开自动化设置，启用 Hasp → System Events。"
        default: return "自动化请求未完成（系统代码 \(code)）。可打开自动化设置检查。"
        }
    }

    func openSettings(_ permission: HaspPermission) -> Bool {
        Self.openSettingsLink(permission)
    }

    static func openSettingsLink(_ permission: HaspPermission, opener: ((URL) -> Bool)? = nil) -> Bool {
        let open = opener ?? { NSWorkspace.shared.open($0) }
        let legacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)")!
        return open(permission.settingsURL) || open(legacy)
    }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged?() }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged?() }
    }
}
