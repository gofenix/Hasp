import Foundation
import IOKit

enum BatteryReader {
    struct Levels {
        var single: Int?
        var left: Int?
        var right: Int?

        var subtitle: String? {
            switch (left, right, single) {
            case let (left?, right?, _):
                return "L \(left)% · R \(right)%"
            case let (left?, nil, _):
                return "L \(left)%"
            case let (nil, right?, _):
                return "R \(right)%"
            case let (_, _, single?):
                return "\(single)%"
            default:
                return nil
            }
        }
    }

    static func levels(forAddress address: String) -> Levels? {
        let wanted = normalize(address)
        guard !wanted.isEmpty else { return nil }
        for serviceName in ["AppleHSBluetoothDevice", "AppleDeviceManagementHIDEventService", "IOBluetoothObject"] {
            if let levels = search(serviceName: serviceName, address: wanted) { return levels }
        }
        return nil
    }

    private static func search(serviceName: String, address: String) -> Levels? {
        guard let matching = IOServiceMatching(serviceName) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            if let levels = read(service, wantedAddress: address) { return levels }
        }
        return nil
    }

    private static func read(_ service: io_registry_entry_t, wantedAddress: String) -> Levels? {
        let address = ["BD_ADDR", "Address", "DeviceAddress", "Bluetooth Address"].compactMap { string(service, $0) }.first
        if let address, normalize(address) != wantedAddress { return nil }
        if address == nil { return nil }
        let levels = Levels(
            single: percent(service, "BatteryPercent") ?? percent(service, "BatteryPercentSingle") ?? percent(service, "BatteryPercentCombined"),
            left: percent(service, "BatteryPercentLeft"),
            right: percent(service, "BatteryPercentRight")
        )
        return levels.subtitle == nil ? nil : levels
    }

    private static func percent(_ service: io_registry_entry_t, _ key: String) -> Int? {
        guard let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        let value: Int?
        if let number = raw as? NSNumber {
            value = number.intValue
        } else if let number = raw as? Int {
            value = number
        } else {
            value = nil
        }
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }

    private static func string(_ service: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }

    private static func normalize(_ address: String) -> String {
        address.filter(\.isHexDigit).lowercased()
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
