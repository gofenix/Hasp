import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    var maximumHeight: CGFloat
    private let initiallyExpanded: Bool
    @State private var otherDevicesExpanded: Bool
    @State private var foldedAppsExpanded: Bool
    @State private var contentHeight: CGFloat = 500
    @State private var headerHeight: CGFloat = 28

    init(maximumHeight: CGFloat = 720, initiallyExpanded: Bool = false) {
        self.maximumHeight = maximumHeight
        self.initiallyExpanded = initiallyExpanded
        _otherDevicesExpanded = State(initialValue: initiallyExpanded)
        _foldedAppsExpanded = State(initialValue: initiallyExpanded)
    }

    private var scrollLimit: CGFloat { max(0, maximumHeight - PanelLayout.footerChrome - headerHeight - PanelLayout.gap) }

    var body: some View {
        VStack(spacing: PanelLayout.gap) {
            PanelHeader(state: model.screenLockState) { model.lockScreen() }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            ScrollView {
                panelContent
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            .frame(width: PanelLayout.contentWidth + 12)
            .frame(height: min(ceil(contentHeight), scrollLimit))
            .padding(.horizontal, -6)
            // Overlay scrollers sit on the segmented control, checkmark and switches.
            .scrollIndicators(.never)
            .scrollDisabled(contentHeight <= scrollLimit)
            .layoutPriority(1)
            Divider()
            footer
                .layoutPriority(2)
        }
        .frame(width: PanelLayout.contentWidth)
        .padding(.horizontal, PanelLayout.inset)
        .padding(.vertical, PanelLayout.verticalInset)
    }

    private var panelContent: some View {
        VStack(spacing: 16) {
            StateScope(state: model.appearanceState) {
                panelSection("外观") { appearanceRow }
            }
            SoundSection(model: model, initiallyExpanded: initiallyExpanded)
            StateScope(state: model.deviceState) {
                panelSection("键盘与鼠标") {
                    if model.bluetoothGate == .ready {
                        deviceSection(items: model.inputs.filter { $0.kind != .other }, empty: "没有已配对的键盘或鼠标")
                        otherDevices
                    } else {
                        bluetoothGate
                    }
                }
            }
            StateScope(state: model.menuState) { menuBarSection }
        }
    }

    private func panelSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionTitle(title: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppearanceSelector(selection: Binding(get: { model.appearanceChoice }, set: { model.selectAppearance($0) }))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("外观模式")
            if model.scheduleMode != .off {
                HStack {
                    Text(model.isDark ? "当前深色" : "当前浅色").foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("随日出日落") { model.selectSchedule(.solar) }
                        Button("18:00 至次日 06:00") { model.selectSchedule(.fixed) }
                        Button("自定义日程…") { model.selectSchedule(.custom); model.openSettings() }
                    } label: {
                        Text(model.scheduleMode == .solar ? "随日出日落" : model.scheduleMode == .fixed ? "18:00–06:00" : "自定义时段")
                            .font(PanelLayout.secondaryFont)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                }
                .font(PanelLayout.secondaryFont)
            }
            if let message = model.permissionMessage {
                Text(message).font(PanelLayout.secondaryFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("重试") { model.selectAppearance(model.appearanceChoice) }
                    Button("自动化设置…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                    }
                }
                .font(PanelLayout.secondaryFont)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bluetoothGate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.bluetoothGate == .denied ? "需要允许使用蓝牙" : "尚未申请蓝牙权限")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("查看权限与访问…") { model.openPermissions() }
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, PanelLayout.textInset)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var otherDevices: some View {
        let items = model.inputs.filter { $0.kind == .other }
        if !items.isEmpty {
            PanelDisclosure(title: "其他已配对设备 · \(items.count)", expanded: $otherDevicesExpanded) {
                deviceSection(items: items, empty: "")
            }
        }
    }

    @ViewBuilder
    private func deviceSection(items: [DeviceItem], empty: String, caption: String? = nil) -> some View {
        if items.isEmpty {
            Text(empty)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, PanelLayout.textInset)
                .padding(.vertical, 10)
        } else {
            VStack(spacing: 0) {
                if let caption {
                    Text(caption)
                        .font(PanelLayout.secondaryFont)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, PanelLayout.textInset)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                }
                ForEach(items) { item in
                    DeviceRow(item: item) { on in
                        model.toggleDevice(item, on: on)
                    }
                }
            }
        }
    }

    private var menuBarSection: some View {
        VStack(spacing: 0) {
            PanelRow(height: PanelLayout.deviceRowHeight) {
                PanelIcon(symbol: "menubar.arrow.up.rectangle", symbolPointSize: 17, symbolWeight: .medium)
                Text("折叠状态栏")
                Spacer(minLength: 4)
                if model.menuState.recoveryPending {
                    Button("恢复显示") { model.setMenuBarFolded(false) }
                        .controlSize(.small).disabled(model.menuState.layoutPending)
                } else {
                    MenuBarFoldSwitch(state: model.menuState) { model.setMenuBarFolded($0) }
                }
            }
            if model.menuState.layoutPending {
                Text(model.menuState.progressDescription)
                    .font(PanelLayout.secondaryFont).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelLayout.textInset)
            }
            if model.menuBarRevealed {
                Text("正在使用原菜单，关闭后恢复折叠")
                    .font(PanelLayout.secondaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelLayout.textInset)
                    .padding(.bottom, 6)
            }
            if let message = model.menuBarMessage {
                Text(message)
                    .font(PanelLayout.secondaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelLayout.textInset)
                if model.menuBarMessageOpensPermissions {
                    Button("检查权限与访问…") { model.openPermissions() }
                        .buttonStyle(.plain).font(PanelLayout.secondaryFont).foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, PanelLayout.textInset)
                }
            }
            if model.menuState.recoveryPending {
                Text("显示状态尚未恢复，恢复前不会显示折叠成功。")
                    .font(PanelLayout.secondaryFont).foregroundStyle(.secondary)
                    .padding(.leading, PanelLayout.textInset)
            }
            if model.menuBarFolded {
                if model.menuBarNeedsAccess {
                    Text("列出 magpie、飞书这些应用需要允许辅助功能。")
                        .font(PanelLayout.secondaryFont)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, PanelLayout.textInset)
                        .padding(.bottom, 2)
                    Button("打开辅助功能设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(PanelLayout.secondaryFont)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelLayout.textInset)
                    .padding(.bottom, 4)
                }
            }
            // Keep the scroll tree and row identities alive across folds.
            // Avoid recreating every button/context menu on each ON/OFF.
            Group {
                if model.menuBarIcons.isEmpty {
                    Text(model.menuState.refreshing ? "正在读取状态栏" : "没有可收起的图标")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, PanelLayout.textInset)
                        .padding(.vertical, 6)
                } else {
                    PanelSectionTitle(title: "已收起的图标")
                        .padding(.top, 8)
                    foldedIconStrip
                    PanelDisclosure(title: "全部 · \(model.menuBarIcons.count)", expanded: $foldedAppsExpanded) {
                        // Applications and system modules read as two groups,
                        // matching how Control Center separates them.
                        let apps = model.menuBarIcons.filter { !$0.id.hasPrefix("system.") }
                        let modules = model.menuBarIcons.filter { $0.id.hasPrefix("system.") }
                        VStack(spacing: 0) {
                            if !apps.isEmpty {
                                foldedGroupCaption("应用")
                                ForEach(apps) { icon in menuBarNameRow(icon) }
                            }
                            if !modules.isEmpty {
                                foldedGroupCaption("系统").padding(.top, apps.isEmpty ? 0 : 6)
                                ForEach(modules) { icon in menuBarNameRow(icon) }
                            }
                        }
                    }
                }
            }
            .frame(height: model.menuBarFolded ? nil : 0)
            .clipped()
            .opacity(model.menuBarFolded ? 1 : 0)
            .allowsHitTesting(model.menuBarFolded)
            .accessibilityHidden(!model.menuBarFolded)
        }
    }

    private var foldedIconStrip: some View {
        let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(Array(model.menuBarIcons.prefix(8))) { icon in
                Button { model.openMenuBarItem(icon) } label: {
                    PanelIcon(symbol: icon.symbol, image: icon.image)
                }
                .buttonStyle(.plain)
                .disabled(model.menuBarOpening)
                .accessibilityLabel(icon.name)
                .accessibilityHint("打开原状态栏菜单")
                .help(icon.status.map { "\(icon.name)：\($0)" } ?? "打开\(icon.name)原菜单")
            }
        }
        .padding(.bottom, 2)
    }

    private func foldedGroupCaption(_ title: String) -> some View {
        Text(title)
            .font(PanelLayout.secondaryFont)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, PanelLayout.textInset)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func menuBarNameRow(_ icon: MenuBarIcon) -> some View {
        Button { model.openMenuBarItem(icon) } label: {
            PanelRow(height: PanelLayout.deviceRowHeight) {
                PanelIcon(symbol: icon.symbol, image: icon.image)
                Text(icon.name).lineLimit(1)
                Spacer(minLength: 0)
                // A trailing chevron implied a sub-page; the row opens the
                // item's own menu, so show its status instead when known.
                if let status = icon.status {
                    Text(status).lineLimit(1)
                        .font(PanelLayout.secondaryFont).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PanelActionStyle())
        .disabled(model.menuBarOpening)
        .accessibilityLabel(icon.name)
        .accessibilityValue(icon.status ?? "")
        .accessibilityHint("打开原状态栏菜单")
        .help(icon.status.map { "\(icon.name)：\($0)" } ?? "打开\(icon.name)原菜单")
        .contextMenu {
            if icon.target != nil && !icon.id.hasPrefix("system.") {
                Button("打开应用主窗口") { model.openMenuBarApplication(icon) }
            }
        }
    }

    private var footer: some View {
        Button { model.openSettings() } label: {
            PanelRow(height: PanelLayout.footerHeight) {
                PanelIcon(symbol: "gearshape")
                Text("设置")
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(PanelActionStyle())
        .accessibilityLabel("设置")
    }
}

struct DeviceRow: View {
    let item: DeviceItem
    let onToggle: (Bool) -> Void

    var body: some View {
        PanelRow(height: PanelLayout.deviceRowHeight) {
            PanelIcon(symbol: item.symbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                if item.pending || item.failed {
                    Text(item.subtitle).font(PanelLayout.secondaryFont).foregroundStyle(.secondary).lineLimit(1)
                } else if !item.connected && item.kind == .other {
                    Text("未连接").font(PanelLayout.secondaryFont).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 2)
            if item.connected && !item.pending, let battery = item.battery {
                Text(battery).font(PanelLayout.secondaryFont).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: PanelLayout.batteryWidth, alignment: .trailing)
            }
            PanelToggle(title: "连接\(item.name)", isOn: Binding(get: { item.switchOn }, set: onToggle))
        }
        .help("\(item.name)\n\(item.subtitle)")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StateScope(state: model.settingsState) {
            SettingsLayout(selection: Binding(get: { model.settingsState.selectedTab }, set: { model.settingsState.selectedTab = $0 })) {
                switch model.settingsState.selectedTab {
                case .general: general
                case .permissions: PermissionSettingsView(center: model.permissions)
                }
            }
        }
    }

    private var general: some View {
        StateScope(state: model.appearanceState) {
            StateScope(state: model.settingsState) {
                Form {
                    Section("自动外观") {
                        Picker("日程", selection: Binding(get: { model.scheduleMode }, set: { model.selectSchedule($0) })) {
                            Text("关闭自动切换").tag(ScheduleMode.off)
                            Text("随日出日落").tag(ScheduleMode.solar)
                            Text("18:00 至次日 06:00").tag(ScheduleMode.fixed)
                            Text("自定义时段").tag(ScheduleMode.custom)
                        }
                        if model.scheduleMode == .custom {
                            DatePicker("深色开始", selection: startDate, displayedComponents: .hourAndMinute)
                            DatePicker("深色结束", selection: endDate, displayedComponents: .hourAndMinute)
                            if model.customStart == model.customEnd {
                                Text("开始与结束相同：不启用深色")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(scheduleSummary)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("通用") {
                        Toggle("登录时打开", isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                    }
                    Section {
                        Button("退出 Hasp") { NSApp.terminate(nil) }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var scheduleSummary: String {
        switch model.scheduleMode {
        case .off: return "自动切换已关闭"
        case .solar: return "日落到次日日出为深色"
        case .fixed: return "18:00 至次日 06:00 为深色"
        case .custom: return ""
        }
    }

    private var startDate: Binding<Date> {
        Binding(
            get: { Self.date(minutes: model.customStart) },
            set: { model.setCustomStart(Self.minutes($0)) }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Self.date(minutes: model.customEnd) },
            set: { model.setCustomEnd(Self.minutes($0)) }
        )
    }

    private static func date(minutes: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let midnight = calendar.startOfDay(for: Date())
        return midnight.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private static func minutes(_ date: Date) -> Int {
        Solar.minuteOfDay(date, timeZone: .current)
    }
}

struct SettingsLayout<Content: View>: View {
    @Binding var selection: SettingsTab
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $selection) {
                Text("通用").tag(SettingsTab.general)
                Text("权限").tag(SettingsTab.permissions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 180)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            Divider()
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 520, idealWidth: 560, minHeight: 460, idealHeight: 540)
    }
}

/// A section subscribes only to its own state. The coordinator itself never
/// broadcasts unrelated updates to the full panel.
private struct StateScope<State: ObservableObject, Content: View>: View {
    @ObservedObject var state: State
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}
