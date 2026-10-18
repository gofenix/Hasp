import Foundation

final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var recentHeadphoneID: String? {
        get { defaults.string(forKey: "recentHeadphoneID") }
        set { defaults.set(newValue, forKey: "recentHeadphoneID") }
    }

    var automaticSchedule: ScheduleMode {
        get { ScheduleMode(rawValue: defaults.string(forKey: "automaticSchedule") ?? "") ?? .solar }
        set { if newValue != .off { defaults.set(newValue.rawValue, forKey: "automaticSchedule") } }
    }

    var scheduleMode: ScheduleMode {
        get { ScheduleMode(rawValue: defaults.string(forKey: "scheduleMode") ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "scheduleMode") }
    }

    var customStart: Int {
        get { defaults.object(forKey: "customStart") as? Int ?? 18 * 60 }
        set { defaults.set(newValue, forKey: "customStart") }
    }

    var customEnd: Int {
        get { defaults.object(forKey: "customEnd") as? Int ?? 6 * 60 }
        set { defaults.set(newValue, forKey: "customEnd") }
    }

    var launchAtLogin: Bool {
        get {
            if defaults.object(forKey: "launchAtLogin") == nil { return true }
            return defaults.bool(forKey: "launchAtLogin")
        }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var latitude: Double? {
        get { defaults.object(forKey: "latitude") as? Double }
        set { defaults.set(newValue, forKey: "latitude") }
    }

    var longitude: Double? {
        get { defaults.object(forKey: "longitude") as? Double }
        set { defaults.set(newValue, forKey: "longitude") }
    }

    var locationIsEstimate: Bool {
        get { defaults.bool(forKey: "locationIsEstimate") }
        set { defaults.set(newValue, forKey: "locationIsEstimate") }
    }

    var didAskLocation: Bool {
        get { defaults.bool(forKey: "didAskLocation") }
        set { defaults.set(newValue, forKey: "didAskLocation") }
    }
}
