import Observation
import Foundation

@MainActor @Observable final class AppearanceState {
    var isDark = false
    var scheduleMode: ScheduleMode = .off
    var customStart = 18 * 60
    var customEnd = 6 * 60
    var permissionMessage: String?
    var scheduleMenuVisible = false
    var requested: Bool?
}

@MainActor @Observable final class AudioState {
    var outputs: [OutputItem] = []
    var recentHeadphoneID: String?
}

@MainActor @Observable final class DeviceState {
    var inputs: [DeviceItem] = []
    var bluetoothGate: BluetoothGate = .pending
}

@MainActor @Observable final class MenuBarState {
    var folded = false
    var icons: [MenuBarIcon] = []
    var revealed = false
    var needsAccess = false
    var message: String?
    /// When true, the fold message may offer Settings → 权限. Mapping conflicts must stay false.
    var messageOpensPermissions = false
    var opening = false
    var refreshing = false
    var layoutPending = false
    var recoveryPending = false

    // The switch reflects the user's request immediately. Native completion
    // is communicated separately; a failed request rolls folded back.
    var switchOn: Bool { folded && !revealed }
    var progressDescription: String {
        revealed ? "正在显示原菜单…" : folded ? "正在折叠状态栏…" : "正在展开状态栏…"
    }
}

enum SettingsTab: Hashable { case general, permissions }

@MainActor @Observable final class SettingsState {
    var launchAtLogin = true
    var selectedTab: SettingsTab = .general
}
