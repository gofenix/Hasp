import Foundation
import CoreBluetooth

struct PairedDevice: Sendable {
    var address: String
    var name: String
    var kind: DeviceKind
    var connected: Bool
}

struct HardwareSnapshot: Sendable {
    var outputs: [ListedOutput]
    var devices: [PairedDevice]
    var batteries: [String: String]
}

/// All synchronous framework and registry reads and mutable battery cache
/// access are confined to queue. Only Sendable value snapshots leave it.
final class HardwareReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.hasp.hardware-snapshot", qos: .userInitiated)
    private let bluetooth: BluetoothService
    private var batteries: [String: String] = [:]
    private var batteryReadAt = Date.distantPast

    init(bluetooth: BluetoothService) { self.bluetooth = bluetooth }

    func read(includeBattery: Bool) async -> HardwareSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                precondition(!Thread.isMainThread)
                let outputs = AudioOutputService.outputs()
                let devices: [PairedDevice]
                if CBCentralManager.authorization == .allowedAlways {
                    devices = bluetooth.pairedDevices().map {
                        PairedDevice(address: $0.address, name: $0.name, kind: $0.kind, connected: $0.connected)
                    }
                } else {
                    devices = []
                }
                if includeBattery && Date().timeIntervalSince(batteryReadAt) >= 10 {
                    var next: [String: String] = [:]
                    for device in devices where device.connected {
                        if let label = BatteryReader.levels(forAddress: device.address)?.subtitle { next[device.address] = label }
                    }
                    batteries = next
                    batteryReadAt = Date()
                }
                continuation.resume(returning: HardwareSnapshot(outputs: outputs, devices: devices, batteries: batteries))
            }
        }
    }
}

struct AppearanceIntent: Equatable, Sendable {
    var dark: Bool
    var fromUser: Bool
    var rollback: ScheduleMode? = nil
}

/// Injected in regression tests, so delayed/failed operations need no live
/// theme, audio routing, device connections or system preference changes.
struct SwitchServices: Sendable {
    var appearance: @Sendable (AppearanceIntent) async -> Bool
    var audio: @Sendable (String) async -> Bool
    var device: @Sendable (String, Bool) async -> Bool
    var snapshot: @Sendable (Bool) async -> HardwareSnapshot
    var availableOutputs: @Sendable () async -> [ListedOutput] = { [] }
    var audioReadyTimeout: TimeInterval = 8

    static func live(bluetooth: BluetoothService) -> Self {
        let reader = HardwareReader(bluetooth: bluetooth)
        return Self(
            appearance: { intent in
                guard await AppearanceService.ensureTargetRunning() else { return false }
                return await Task.detached {
                    if !intent.fromUser && !AppearanceService.canReadWithoutPrompt() { return false }
                    return AppearanceService.setDark(intent.dark)
                }.value
            },
            audio: { uid in await Task.detached { AudioOutputService.select(uid: uid) }.value },
            device: { address, connected in
                await Task.detached { connected ? bluetooth.connect(address: address) : bluetooth.disconnect(address: address) }.value
            },
            snapshot: { includeBattery in await reader.read(includeBattery: includeBattery) },
            availableOutputs: { await Task.detached { AudioOutputService.outputs() }.value }
        )
    }
}
