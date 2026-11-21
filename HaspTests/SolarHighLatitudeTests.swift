import Foundation

@main
enum SolarHighLatitudeTests {
    static func main() {
        testReykjavikMidnightSunset()
        testTromsoPolarNight()
        testTromsoPolarDay()
        testSvalbardExtremeConditions()
        testSouthernHemisphereSolstices()
        testStandardLatitudeRegression()
        print("SolarHighLatitudeTests passed: verified Reykjavik midnight sunset, Tromso polar night & day, Svalbard, Antarctica, and Shanghai baseline.")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL \(message)\n", stderr)
            exit(1)
        }
    }

    /// Defect 5: High latitude summer where sunset crosses midnight (sunset < sunrise on calendar day).
    /// Reykjavik (64.1466° N, 21.9426° W), 2026-06-21.
    private static func testReykjavikMidnightSunset() {
        let reykjavikTZ = TimeZone(identifier: "Atlantic/Reykjavik") ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reykjavikTZ

        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let events = Solar.sunriseSunset(on: date, latitude: 64.1466, longitude: -21.9426, timeZone: reykjavikTZ)
        expect(events != nil, "Reykjavik solstice has sunrise and sunset events")

        if let events {
            expect(events.sunset < events.sunrise, "Reykjavik sunset occurs past midnight before sunrise (sunset < sunrise)")
        }

        // 12:00 (Noon) must be daytime (light mode / not dark)
        let noon = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12, minute: 0))!
        expect(!Solar.isSolarDark(at: noon, latitude: 64.1466, longitude: -21.9426, timeZone: reykjavikTZ),
               "Reykjavik noon on summer solstice must be daylight (not dark)")

        // 00:01 (Before 00:03 sunset) must be daylight (sun from previous day has not set yet)
        let beforeSunset = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0, minute: 1))!
        expect(!Solar.isSolarDark(at: beforeSunset, latitude: 64.1466, longitude: -21.9426, timeZone: reykjavikTZ),
               "Reykjavik 00:01 before sunset must be daylight")

        // 01:30 (Between 00:03 sunset and 02:54 sunrise) must be dark
        let night = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 1, minute: 30))!
        expect(Solar.isSolarDark(at: night, latitude: 64.1466, longitude: -21.9426, timeZone: reykjavikTZ),
               "Reykjavik 01:30 between sunset and sunrise must be dark")

        // 03:30 (After 02:54 sunrise) must be daylight
        let afterSunrise = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 3, minute: 30))!
        expect(!Solar.isSolarDark(at: afterSunrise, latitude: 64.1466, longitude: -21.9426, timeZone: reykjavikTZ),
               "Reykjavik 03:30 after sunrise must be daylight")
    }

    /// Defect 6: Polar night where sun never rises (Tromsø 69.6492° N, 18.9553° E, 2026-12-21).
    private static func testTromsoPolarNight() {
        let osloTZ = TimeZone(identifier: "Europe/Oslo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = osloTZ

        let winterSolstice = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        let events = Solar.sunriseSunset(on: winterSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ)
        expect(events == nil, "Tromso on winter solstice has no sunrise or sunset (polar night)")
        expect(Solar.isPolarNight(on: winterSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso on winter solstice must be classified as polar night")
        expect(!Solar.isPolarDay(on: winterSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso on winter solstice must not be classified as polar day")

        // In polar night, 12:00 noon must still be dark!
        expect(Solar.isSolarDark(at: winterSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso noon on winter solstice must be dark (polar night)")

        let midnight = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 0, minute: 30))!
        expect(Solar.isSolarDark(at: midnight, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso midnight on winter solstice must be dark")
    }

    /// Polar day where sun never sets (Tromsø 69.6492° N, 18.9553° E, 2026-06-21).
    private static func testTromsoPolarDay() {
        let osloTZ = TimeZone(identifier: "Europe/Oslo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = osloTZ

        let summerSolstice = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let events = Solar.sunriseSunset(on: summerSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ)
        expect(events == nil, "Tromso on summer solstice has no sunrise or sunset (polar day / midnight sun)")
        expect(Solar.isPolarDay(on: summerSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso on summer solstice must be classified as polar day")
        expect(!Solar.isPolarNight(on: summerSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso on summer solstice must not be classified as polar night")

        // In polar day, midnight must still be light!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0, minute: 30))!
        expect(!Solar.isSolarDark(at: midnight, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso midnight on summer solstice must be daylight (midnight sun)")
        expect(!Solar.isSolarDark(at: summerSolstice, latitude: 69.6492, longitude: 18.9553, timeZone: osloTZ),
               "Tromso noon on summer solstice must be daylight")
    }

    /// Extreme Arctic conditions: Longyearbyen, Svalbard (78.22° N, 15.65° E).
    private static func testSvalbardExtremeConditions() {
        let osloTZ = TimeZone(identifier: "Europe/Oslo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = osloTZ

        let winter = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        expect(Solar.isPolarNight(on: winter, latitude: 78.22, longitude: 15.65, timeZone: osloTZ), "Svalbard winter is polar night")
        expect(Solar.isSolarDark(at: winter, latitude: 78.22, longitude: 15.65, timeZone: osloTZ), "Svalbard winter noon is dark")

        let summer = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0, minute: 30))!
        expect(Solar.isPolarDay(on: summer, latitude: 78.22, longitude: 15.65, timeZone: osloTZ), "Svalbard summer is polar day")
        expect(!Solar.isSolarDark(at: summer, latitude: 78.22, longitude: 15.65, timeZone: osloTZ), "Svalbard summer midnight is daylight")
    }

    /// Southern Hemisphere verification: McMurdo Station, Antarctica (77.85° S, 166.66° E).
    private static func testSouthernHemisphereSolstices() {
        let mcmurdoTZ = TimeZone(identifier: "Antarctica/McMurdo") ?? TimeZone(secondsFromGMT: 12 * 3600)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mcmurdoTZ

        // June 21 is Winter in Southern Hemisphere (Polar Night)
        let juneSolstice = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        expect(Solar.isPolarNight(on: juneSolstice, latitude: -77.85, longitude: 166.66, timeZone: mcmurdoTZ),
               "Antarctica in June must be polar night")
        expect(Solar.isSolarDark(at: juneSolstice, latitude: -77.85, longitude: 166.66, timeZone: mcmurdoTZ),
               "Antarctica noon in June must be dark")

        // December 21 is Summer in Southern Hemisphere (Polar Day)
        let decSolstice = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 0, minute: 30))!
        expect(Solar.isPolarDay(on: decSolstice, latitude: -77.85, longitude: 166.66, timeZone: mcmurdoTZ),
               "Antarctica in December must be polar day")
        expect(!Solar.isSolarDark(at: decSolstice, latitude: -77.85, longitude: 166.66, timeZone: mcmurdoTZ),
               "Antarctica midnight in December must be daylight")
    }

    /// Regression baseline check: Standard latitude (Shanghai 31.23° N, 121.47° E) works as before.
    private static func testStandardLatitudeRegression() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai

        let solsticeNoon = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let solsticeMidnight = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0, minute: 30))!

        expect(!Solar.isPolarNight(on: solsticeNoon, latitude: 31.23, longitude: 121.47, timeZone: shanghai), "Shanghai is never polar night")
        expect(!Solar.isPolarDay(on: solsticeNoon, latitude: 31.23, longitude: 121.47, timeZone: shanghai), "Shanghai is never polar day")
        expect(!Solar.isSolarDark(at: solsticeNoon, latitude: 31.23, longitude: 121.47, timeZone: shanghai), "Shanghai noon is light")
        expect(Solar.isSolarDark(at: solsticeMidnight, latitude: 31.23, longitude: 121.47, timeZone: shanghai), "Shanghai 00:30 is dark")
    }
}
