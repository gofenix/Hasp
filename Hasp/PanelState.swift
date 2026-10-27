import Combine
import Foundation

@MainActor final class AppearanceState: ObservableObject {
    @Published var isDark = false
    @Published var scheduleMode: ScheduleMode = .off
    @Published var customStart = 18 * 60
    @Published var customEnd = 6 * 60
    @Published var permissionMessage: String?
    @Published var scheduleMenuVisible = false
    @Published var requested: Bool?
}

@MainActor final class AudioState: ObservableObject {
    @Published var outputs: [OutputItem] = []
    @Published var recentHeadphoneID: String?
}

@MainActor final class DeviceState: ObservableObject {
    @Published var inputs: [DeviceItem] = []
    @Published var bluetoothGate: BluetoothGate = .pending
}

@MainActor final class MenuBarState: ObservableObject {
    @Published var folded = false
    @Published var icons: [MenuBarIcon] = []
    @Published var revealed = false
    @Published var needsAccess = false
    @Published var message: String?
    /// When true, the fold message may offer Settings → 权限. Mapping conflicts must stay false.
    @Published var messageOpensPermissions = false
    @Published var opening = false
    @Published var refreshing = false
    @Published var layoutPending = false
    @Published var recoveryPending = false

    // The switch reflects the user's request immediately. Native completion
    // is communicated separately; a failed request rolls folded back.
    var switchOn: Bool { folded && !revealed }
    var progressDescription: String {
        revealed ? "正在显示原菜单…" : folded ? "正在折叠状态栏…" : "正在展开状态栏…"
    }
}

enum SettingsTab: Hashable { case general, permissions }

@MainActor final class SettingsState: ObservableObject {
    @Published var launchAtLogin = true
    @Published var selectedTab: SettingsTab = .general
}
