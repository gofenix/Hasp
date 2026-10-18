import CoreAudio
import Foundation

enum AudioOutputInventory {
    private static let addressPattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])|(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])"#)

    static func addressKey(_ address: String) -> String {
        SystemBluetoothCatalog.normalize(address)
    }

    /// Bluetooth Core Audio UIDs include the device address and endpoint suffix
    /// (for example AA-BB-CC-DD-EE-FF:output). Never route by a display name:
    /// two paired headphones can have identical names.
    static func bluetoothAddress(_ output: ListedOutput) -> String? {
        guard output.transport == kAudioDeviceTransportTypeBluetooth ||
                output.transport == kAudioDeviceTransportTypeBluetoothLE else { return nil }
        let uid = output.uid as NSString
        guard let match = addressPattern.firstMatch(in: output.uid, range: NSRange(location: 0, length: uid.length)) else { return nil }
        return addressKey(uid.substring(with: match.range))
    }

    static func endpoint(for address: String, in outputs: [ListedOutput]) -> ListedOutput? {
        let matches = outputs.filter { bluetoothAddress($0) == addressKey(address) }
        return matches.first(where: \.isCurrent) ?? matches.first
    }

    static func items(_ snapshot: HardwareSnapshot) -> [OutputItem] {
        var result: [OutputItem] = []
        var usedAddresses = Set<String>()
        var endpoints: [String: [ListedOutput]] = [:]
        for output in snapshot.outputs {
            if let address = bluetoothAddress(output) { endpoints[address, default: []].append(output) }
        }
        for device in snapshot.devices {
            let key = addressKey(device.address)
            let candidates = endpoints[key] ?? []
            let output = candidates.first(where: \.isCurrent) ?? candidates.first
            guard device.kind == .headphone || output != nil else { continue }
            guard usedAddresses.insert(key).inserted else { continue }
            let connected = device.connected || output != nil
            result.append(OutputItem(id: "bluetooth:\(key)", name: device.name, kind: .bluetooth,
                isCurrent: output?.isCurrent ?? false, pending: false,
                battery: connected ? snapshot.batteries[device.address] : nil,
                bluetoothAddress: device.address, audioUID: output?.uid, connected: connected))
        }
        var usedUIDs = Set<String>()
        for output in snapshot.outputs {
            if let address = bluetoothAddress(output), usedAddresses.contains(address) { continue }
            guard usedUIDs.insert(output.uid).inserted else { continue }
            result.append(OutputItem(id: output.uid, name: output.name,
                kind: OutputKind.classify(name: output.name, transport: output.transport),
                isCurrent: output.isCurrent, pending: false, audioUID: output.uid))
        }
        return result
    }
}
