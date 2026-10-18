import Foundation
import IOBluetooth

@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
private func IOBluetoothPreferenceGetControllerPowerState() -> Int32

@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
private func IOBluetoothPreferenceSetControllerPowerState(_ state: Int32)

// Notification registrations belong to main; worker reads use watchDisconnects
// false and connection commands touch no mutable registration state.
final class BluetoothService: NSObject, @unchecked Sendable {
    var onDevicesChanged: (() -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private let pageTimeout: BluetoothHCIPageTimeout = 24_000

    func start() {
        precondition(Thread.isMainThread)
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func watchDevices(addresses: [String]) {
        precondition(Thread.isMainThread)
        // Repeated snapshots already have these registrations. Avoid native
        // device lookups on the UI thread for every unchanged address.
        let missing = addresses.filter { disconnectNotifications[$0] == nil }
        guard !missing.isEmpty else { return }
        refreshDisconnectWatches(missing.compactMap { IOBluetoothDevice(addressString: $0) })
    }

    func isPoweredOn() -> Bool {
        if IOBluetoothPreferenceGetControllerPowerState() == 1 { return true }
        return IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    func ensurePowered() -> Bool {
        if isPoweredOn() { return true }
        IOBluetoothPreferenceSetControllerPowerState(1)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if isPoweredOn() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return isPoweredOn()
    }

    func pairedDevices(watchDisconnects: Bool = true) -> [(address: String, name: String, kind: DeviceKind, connected: Bool)] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        if watchDisconnects {
            refreshDisconnectWatches(devices)
        }
        let catalog = SystemBluetoothCatalog.kindsByAddress()
        SystemBluetoothCatalog.refresh { [weak self] in self?.onDevicesChanged?() }
        return devices.compactMap { device in
            let name = device.name ?? device.nameOrAddress ?? ""
            let address = device.addressString ?? ""
            guard !address.isEmpty else { return nil }
            let kind = DeviceClassifier.classify(name: name, classOfDevice: device.classOfDevice)
                ?? catalog[SystemBluetoothCatalog.normalize(address)]
                ?? .other
            return (address, name.isEmpty ? "蓝牙设备" : name, kind, device.isConnected())
        }
    }

    func connect(address: String) -> Bool {
        guard ensurePowered(), let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() { return true }
        _ = device.openConnection(nil, withPageTimeout: pageTimeout, authenticationRequired: false)
        return device.isConnected()
    }

    func disconnect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if !device.isConnected() { return true }
        _ = device.closeConnection()
        return !device.isConnected()
    }

    private func refreshDisconnectWatches(_ devices: [IOBluetoothDevice]? = nil) {
        let devices = devices ?? ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [])
        for device in devices {
            guard let address = device.addressString, disconnectNotifications[address] == nil else { continue }
            disconnectNotifications[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in self?.onDevicesChanged?() }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in self?.onDevicesChanged?() }
    }
}
