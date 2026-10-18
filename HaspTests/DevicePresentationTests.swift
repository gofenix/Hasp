import Foundation

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

@main enum DevicePresentationTests {
    static func main() {
        var device = DeviceItem(address: "test", name: "Keyboard", kind: .keyboard,
                                connected: false, pending: false, failed: false)
        precondition(!device.switchOn)
        device.pending = true
        device.pendingConnection = true
        precondition(device.switchOn && device.subtitle == "正在连接")
        device.pending = false
        device.pendingConnection = nil
        device.connected = true
        precondition(device.switchOn)
        device.pending = true
        device.pendingConnection = false
        precondition(!device.switchOn && device.subtitle == "正在断开")
        // Failure rolls back to the real connected state and remains actionable.
        device.pending = false
        device.pendingConnection = nil
        device.failed = true
        precondition(device.switchOn && device.subtitle == "未能断开，请重试")
        device.connected = false
        precondition(!device.switchOn && device.subtitle == "未能连接，请重试")
        var output = OutputItem(id: "test", name: "Headphones", kind: .bluetooth,
                                isCurrent: false, pending: false, failed: true)
        precondition(output.subtitle == "切换失败，请重试")
        output.pending = true
        precondition(output.subtitle == "正在切换")
        output.pending = false
        output.failed = false
        output.isCurrent = true
        precondition(output.symbolName == "headphones")
        print("ok: connection, disconnection, rollback and audio failure presentation")
    }
}
