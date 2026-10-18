import Foundation

enum DeviceKind: String, Sendable {
    case headphone
    case keyboard
    case mouse
    case trackpad
    case other

    var symbolName: String {
        switch self {
        case .headphone: "headphones"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .other: "antenna.radiowaves.left.and.right"
        }
    }
}

enum DeviceClassifier {
    static func classify(name: String, classOfDevice: UInt32) -> DeviceKind? {
        let major = (classOfDevice & 0x1F00) >> 8
        let minor = (classOfDevice & 0xFC) >> 2
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        if major == 0x04 {
            switch minor {
            case 0x01, 0x02, 0x06:
                return .headphone
            default:
                return nil
            }
        }

        if major == 0x05 {
            let group = minor & 0x30
            if group == 0x10 { return .keyboard }
            if group == 0x20 || group == 0x30 {
                if containsTrackpad(folded) { return .trackpad }
                if group == 0x20 || containsMouse(folded) { return .mouse }
                return .keyboard
            }
        }

        if major == 0 || major == 0x1F || major == 0x07 {
            if containsHeadphone(folded) { return .headphone }
            if containsTrackpad(folded) { return .trackpad }
            if containsKeyboard(folded) { return .keyboard }
            if containsMouse(folded) { return .mouse }
        }
        return nil
    }

    static func classify(systemMinorType: String) -> DeviceKind? {
        switch systemMinorType.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) {
        case "mouse":
            return .mouse
        case "keyboard":
            return .keyboard
        case "trackpad", "magic trackpad":
            return .trackpad
        case "headphones", "headset":
            return .headphone
        default:
            return nil
        }
    }

    private static func containsTrackpad(_ name: String) -> Bool {
        name.contains("trackpad") || name.contains("触控板")
    }

    private static func containsMouse(_ name: String) -> Bool {
        name.contains("mouse") || name.contains("鼠标")
    }

    private static func containsKeyboard(_ name: String) -> Bool {
        name.contains("keyboard") || name.contains("键盘")
    }

    private static func containsHeadphone(_ name: String) -> Bool {
        ["airpod", "beats", "headphone", "headset", "earbud", "buds", "耳机"].contains { name.contains($0) }
    }
}
