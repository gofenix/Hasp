import SwiftUI

struct SoundSection: View {
    let model: AppModel
    private var state: AudioState
    @State private var expanded: Bool

    init(model: AppModel, initiallyExpanded: Bool = false) {
        self.model = model
        state = model.audioState
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let available = state.outputs.filter { !$0.isInPairedGroup }
        let paired = state.outputs.filter(\.isInPairedGroup)
        let featured = paired.first { $0.id == state.recentHeadphoneID } ?? paired.first
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionTitle(title: "声音输出")
            if available.isEmpty {
                Text("没有可用的输出")
                    .font(PanelLayout.secondaryFont).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelLayout.textInset).padding(.vertical, 10)
            }
            ForEach(available) { row($0) }
            if let featured {
                PanelSectionTitle(title: paired.contains(where: \.connected) ? "已配对耳机" : "未连接的耳机")
                    .padding(.top, 12)
                row(featured)
                let more = paired.filter { $0.id != featured.id }
                if !more.isEmpty {
                    PanelDisclosure(title: "更多未连接耳机 · \(more.count)", expanded: $expanded) {
                        ForEach(more) { row($0) }
                    }
                }
            }
        }
    }

    private func row(_ item: OutputItem) -> some View {
        SoundOutputRow(item: item, onUse: { model.activateOutput(item) },
                       onDisconnect: { model.disconnectOutput(item) })
    }
}

struct PanelDisclosure<Content: View>: View {
    let title: String
    @Binding var expanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                PanelRow(height: 28) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: PanelLayout.iconSize)
                    Text(title).font(PanelLayout.secondaryFont)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(PanelActionStyle())
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded { VStack(spacing: 0, content: content) }
        }
    }
}

struct SoundOutputRow: View {
    let item: OutputItem
    let onUse: () -> Void
    let onDisconnect: () -> Void

    private var status: String {
        if let failure = item.failure {
            switch failure {
            case .connection: return "连接失败"
            case .routing: return item.connected ? "已连接，声音切换失败" : "声音切换失败"
            case .disconnection: return "断开失败"
            }
        }
        if item.pending { return item.subtitle }
        if item.isCurrent {
            return "当前输出 · " + (item.bluetoothAddress != nil ? "蓝牙" : item.kind.label)
                + (item.battery.map { " · \($0)" } ?? "")
        }
        if item.bluetoothAddress != nil {
            return item.connected ? "蓝牙 · 已连接" + (item.battery.map { " · \($0)" } ?? "") : "未连接"
        }
        return item.kind.label
    }

    @ViewBuilder private var trailing: some View {
        if item.pending {
            ProgressView().controlSize(.small)
        } else if item.failure == .disconnection {
            actionChip("重试断开")
        } else if item.failure != nil || item.failed {
            actionChip("重试")
        } else if item.isCurrent {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: PanelLayout.accessoryWidth)
        } else if item.bluetoothAddress != nil && !item.connected {
            actionChip("连接")
        }
    }

    private func actionChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1)
            }
            .padding(.trailing, 2)
    }

    var body: some View {
        PanelHoverRow {
            PanelRow {
                Button(action: onUse) {
                    PanelRow {
                        PanelIcon(symbol: item.symbolName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).fontWeight(item.isCurrent ? .medium : .regular).lineLimit(1)
                            Text(status.isEmpty ? "输出" : status).font(PanelLayout.secondaryFont).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        trailing
                    }
                }
                .buttonStyle(.plain)
                .disabled(item.pending)
                .help("\(item.name)\n\(item.subtitle)")
                .accessibilityLabel("\(item.name)，\(item.subtitle)")
                .accessibilityValue(item.isCurrent ? "当前声音输出" : item.failure == .disconnection ? "重试断开" : item.actionTitle)
                if item.bluetoothAddress != nil && item.connected {
                    PanelMoreMenu {
                        Button(item.failure == .disconnection ? "重试断开蓝牙连接" : "断开蓝牙连接", action: onDisconnect)
                            .disabled(item.pending)
                    }
                    .help("\(item.name)的连接操作")
                    .accessibilityLabel("\(item.name)的连接操作")
                }
            }
        }
        .contextMenu {
            if item.bluetoothAddress != nil && item.connected {
                Button("断开蓝牙连接", action: onDisconnect).disabled(item.pending)
            }
        }
    }
}
