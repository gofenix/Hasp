import Foundation

@main
enum HaspTests {
    static func main() {
        expect(Solar.isDark(minute: 19 * 60, start: 18 * 60, end: 6 * 60), "19:00 inside overnight window")
        expect(Solar.isDark(minute: 3 * 60, start: 18 * 60, end: 6 * 60), "03:00 inside overnight window")
        expect(!Solar.isDark(minute: 12 * 60, start: 18 * 60, end: 6 * 60), "12:00 outside overnight window")
        expect(!Solar.isDark(minute: 6 * 60, start: 18 * 60, end: 6 * 60), "06:00 is the exclusive end")
        expect(Solar.isDark(minute: 18 * 60, start: 18 * 60, end: 6 * 60), "18:00 is the inclusive start")
        expect(Solar.isDark(minute: 10 * 60, start: 9 * 60, end: 17 * 60), "10:00 inside daytime window")
        expect(!Solar.isDark(minute: 8 * 60, start: 9 * 60, end: 17 * 60), "08:00 outside daytime window")
        expect(!Solar.isDark(minute: 17 * 60, start: 9 * 60, end: 17 * 60), "17:00 is the exclusive end")
        expect(!Solar.isDark(minute: 12 * 60, start: 8 * 60, end: 8 * 60), "empty window is never dark")

        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let solstice = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let events = Solar.sunriseSunset(on: solstice, latitude: 31.23, longitude: 121.47, timeZone: shanghai)
        expect(events != nil, "Shanghai solstice has a sunrise and sunset")
        if let events {
            let rise = Solar.minuteOfDay(events.sunrise, timeZone: shanghai)
            let set = Solar.minuteOfDay(events.sunset, timeZone: shanghai)
            expect(rise > 4 * 60 && rise < 6 * 60, "Shanghai sunrise on 2026-06-21 is between 04:00 and 06:00, got \(rise)")
            expect(set > 18 * 60 && set < 20 * 60, "Shanghai sunset on 2026-06-21 is between 18:00 and 20:00, got \(set)")
        }
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0, minute: 30))!
        expect(!Solar.isSolarDark(at: solstice, latitude: 31.23, longitude: 121.47, timeZone: shanghai), "noon is light")
        expect(Solar.isSolarDark(at: midnight, latitude: 31.23, longitude: 121.47, timeZone: shanghai), "00:30 is dark")
        expect(Solar.formatRange(start: 18 * 60, end: 6 * 60) == "18:00–06:00", "range uses an en dash")

        expect(DeviceClassifier.classify(name: "AirPods Pro", classOfDevice: cod(major: 0x04, minor: 0x06)) == .headphone, "headphones")
        expect(DeviceClassifier.classify(name: "Living Room", classOfDevice: cod(major: 0x04, minor: 0x05)) == nil, "speaker excluded")
        expect(DeviceClassifier.classify(name: "Car", classOfDevice: cod(major: 0x04, minor: 0x08)) == nil, "car audio excluded")
        expect(DeviceClassifier.classify(name: "Magic Keyboard", classOfDevice: cod(major: 0x05, minor: 0x10)) == .keyboard, "keyboard")
        expect(DeviceClassifier.classify(name: "Magic Mouse", classOfDevice: cod(major: 0x05, minor: 0x20)) == .mouse, "mouse")
        expect(DeviceClassifier.classify(name: "Magic Trackpad", classOfDevice: cod(major: 0x05, minor: 0x20)) == .trackpad, "trackpad by name")
        expect(DeviceClassifier.classify(name: "MacBook Pro", classOfDevice: cod(major: 0x01, minor: 0x03)) == nil, "computer excluded")
        expect(DeviceClassifier.classify(name: "iPad", classOfDevice: cod(major: 0x01, minor: 0x04)) == nil, "iPad excluded")
        expect(DeviceClassifier.classify(name: "Beats Fit Pro", classOfDevice: 0) == .headphone, "name fallback for headphones")
        expect(DeviceClassifier.classify(name: "Magic Mouse", classOfDevice: 0) == .mouse, "name fallback for mouse")
        expect(DeviceClassifier.classify(name: "Magic Keyboard", classOfDevice: 0) == .keyboard, "name fallback for keyboard")
        expect(DeviceClassifier.classify(systemMinorType: "Mouse") == .mouse, "system mouse")
        expect(DeviceClassifier.classify(systemMinorType: "Keyboard") == .keyboard, "system keyboard")
        expect(DeviceClassifier.classify(systemMinorType: "Magic Trackpad") == .trackpad, "system trackpad")
        expect(DeviceClassifier.classify(systemMinorType: "Computer") == nil, "computer minor type excluded")
        print("ok")
    }
}

private func cod(major: UInt32, minor: UInt32) -> UInt32 { (major << 8) | (minor << 2) }

private func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}
