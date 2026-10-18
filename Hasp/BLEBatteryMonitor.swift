import CoreBluetooth
import Foundation

final class BLEBatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onUpdate: (() -> Void)?

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")
    private let queue = DispatchQueue(label: "app.hasp.ble-battery", qos: .utility)
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var pending = 0
    private var reading = false
    private var lastRefresh = Date.distantPast
    private let lock = NSLock()
    private var levels: [String: String] = [:]

    func level(named name: String) -> String? {
        let key = Self.fold(name)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let exact = levels[key] { return exact }
        return levels.first { key.contains($0.key) || $0.key.contains(key) }?.value
    }

    func refresh() {
        // CoreBluetooth delegates and refresh requests share one serial queue.
        // The panel must not race the delegate's pending/reading state.
        queue.async { [weak self] in self?.refreshOnQueue() }
    }

    private func refreshOnQueue() {
        if reading { return }
        if !levels.isEmpty, Date().timeIntervalSince(lastRefresh) < 8 { return }
        lastRefresh = Date()
        if central == nil {
            reading = true
            central = CBCentralManager(delegate: self, queue: queue)
            return
        }
        readConnected()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            reading = false
            return
        }
        readConnected()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishOne()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        if services.isEmpty {
            finishOne()
            return
        }
        for service in services {
            peripheral.discoverCharacteristics([batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        if characteristics.isEmpty {
            finishOne()
            return
        }
        for characteristic in characteristics {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let byte = characteristic.value?.first, (0...100).contains(Int(byte)), let name = peripheral.name {
            let label = "\(byte)%"
            lock.lock()
            levels[Self.fold(name)] = label
            lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.onUpdate?() }
        }
        central?.cancelPeripheralConnection(peripheral)
        finishOne()
    }

    private func readConnected() {
        guard let central, central.state == .poweredOn else {
            reading = false
            return
        }
        let found = central.retrieveConnectedPeripherals(withServices: [batteryService])
        guard !found.isEmpty else {
            reading = false
            return
        }
        reading = true
        pending = found.count
        for peripheral in found {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state == .connected {
                peripheral.discoverServices([batteryService])
            } else {
                central.connect(peripheral, options: nil)
            }
        }
    }

    private func finishOne() {
        pending -= 1
        if pending <= 0 {
            pending = 0
            reading = false
        }
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
