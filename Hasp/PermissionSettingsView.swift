import AppKit
import Combine
import SwiftUI

struct PermissionSettingsView: View {
    @ObservedObject var center: PermissionCenter
    private let bundleURL: URL
    @State private var appeared = false
    @State private var helpExpanded: Bool

    init(center: PermissionCenter, initiallyExpanded: Bool = false, bundleURL: URL = Bundle.main.bundleURL) {
        self.center = center
        self.bundleURL = bundleURL
        _helpExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("权限与访问")
                            .font(.system(size: 20, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("管理 Hasp 使用的系统权限，按需开启。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(HaspPermission.usedPermissions.enumerated()), id: \.element.id) { index, permission in
                            if index > 0 { Divider().padding(.leading, 48) }
                            permissionRow(permission)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    DisclosureGroup(isExpanded: $helpExpanded) {
                        authorizationHelp.padding(.top, 10)
                    } label: {
                        Text("如何授权").font(.system(size: 12))
                    }
                    .tint(.secondary)
                    .accessibilityIdentifier("permission-help")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 8) {
                Text("查看状态不会弹出授权提示")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                ZStack {
                    Color.clear
                    if center.refreshing { ProgressView().controlSize(.mini) }
                }
                .frame(width: 14, height: 14)
                .accessibilityHidden(!center.refreshing)
                Button("重新检查") { Task { await center.refresh(manual: true) } }
                    .controlSize(.small)
                    .disabled(center.refreshing)
                    .help("检查当前状态，不会申请权限")
                    .accessibilityIdentifier("permission-refresh")
            }
            .padding(.horizontal, 24)
            .frame(height: 44)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { appeared = true; await center.refresh() }
        .onDisappear { appeared = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshIfVisible() }
    }

    private func permissionRow(_ permission: HaspPermission) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(permission.settingsTitle).font(.system(size: 13, weight: .medium))
                    if permission == .location {
                        Text("可选").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Text(permission.settingsSummary)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let feedback = center.feedback[permission] {
                    Text(feedback)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            permissionControl(permission)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .contain)
    }

    private func permissionControl(_ permission: HaspPermission) -> some View {
        let status = center.status(permission)
        return VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 5) {
                if status.granted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(status.label).foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .fixedSize()
            if let action = status.action(for: permission) {
                Button(action) { Task { await center.performAction(permission) } }
                    .controlSize(.small)
                    .disabled(center.pending.contains(permission))
                    .accessibilityLabel("\(permission.title)：\(action)")
                if center.pending.contains(permission) {
                    Text("等待系统响应…").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if action == "申请授权", center.feedback[permission] != nil {
                    Button("打开设置") { center.openSettings(permission) }
                        .controlSize(.small)
                        .accessibilityLabel("\(permission.title)：打开设置")
                }
            }
        }
    }

    private var authorizationHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点击对应权限的「申请授权」或「打开设置」。系统列表中没有 Hasp 时，可将下方图标拖入列表，或点「+」添加。")
            HStack(spacing: 10) {
                Label {
                    Text("Hasp.app").fontWeight(.medium)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: bundleURL.path))
                        .resizable().frame(width: 28, height: 28)
                }
                .onDrag { NSItemProvider(object: bundleURL as NSURL) }
                .help("将 Hasp 拖入辅助功能或完全磁盘访问列表")
                .accessibilityHint("可拖入系统设置的权限列表")
                Spacer(minLength: 8)
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([bundleURL]) }
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bundleURL.path, forType: .string)
                }
            }
            .controlSize(.small)
            Text("定位仅用于日出日落，固定时段无需定位。菜单栏配置访问仅用于 macOS 27 的状态栏折叠，外观、声音和蓝牙无需此访问。")
            Text("菜单栏配置状态表示实际读取能力，不代表完整磁盘访问的全部授权状态。授权由 macOS 确认；若系统提示重新打开 Hasp，请按提示操作。")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func refreshIfVisible() {
        guard appeared, NSApp.windows.contains(where: { $0.identifier?.rawValue == "hasp.settings" && $0.isVisible }) else { return }
        Task { await center.refreshAfterChange() }
    }
}

private extension HaspPermission {
    var settingsTitle: String { self == .automation ? "自动化" : title }
    var settingsSummary: String {
        switch self {
        case .accessibility: return "读取并打开状态栏应用的原生菜单"
        case .automation: return "通过 System Events 切换系统外观"
        case .bluetooth: return "显示已配对设备，连接或断开耳机"
        case .location: return "按所在地日出日落切换外观"
        case .menuConfiguration: return "用于 macOS 27 的状态栏折叠"
        }
    }
}
