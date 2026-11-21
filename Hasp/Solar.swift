import Foundation

enum ScheduleMode: String, Sendable {
    case off
    case solar
    case fixed
    case custom
}

enum Solar {
    /// Dark when `minute` falls inside [start, end). A window with start > end crosses midnight.
    static func isDark(minute: Int, start: Int, end: Int) -> Bool {
        let minute = normalizeMinute(minute)
        let start = normalizeMinute(start)
        let end = normalizeMinute(end)
        if start == end { return false }
        if start < end {
            return minute >= start && minute < end
        }
        return minute >= start || minute < end
    }

    static func isDark(
        at date: Date,
        mode: ScheduleMode,
        customStart: Int,
        customEnd: Int,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> Bool {
        switch mode {
        case .off:
            return false
        case .fixed:
            return isDark(minute: minuteOfDay(date, timeZone: timeZone), start: 18 * 60, end: 6 * 60)
        case .custom:
            return isDark(minute: minuteOfDay(date, timeZone: timeZone), start: customStart, end: customEnd)
        case .solar:
            return isSolarDark(at: date, latitude: latitude, longitude: longitude, timeZone: timeZone)
        }
    }

    static func minuteOfDay(_ date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func isSolarDark(at date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> Bool {
        if let events = sunriseSunset(on: date, latitude: latitude, longitude: longitude, timeZone: timeZone) {
            if events.sunrise <= events.sunset {
                return date < events.sunrise || date >= events.sunset
            } else {
                return date >= events.sunset && date < events.sunrise
            }
        }
        return isPolarNight(on: date, latitude: latitude, longitude: longitude, timeZone: timeZone)
    }

    /// Evaluates the cosine of the local hour angle at solar noon to identify polar day/night.
    private static func solarNoonCosHour(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }

        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: midnight) ?? day)
        let lngHour = longitude / 15
        let zenith = 90.833
        let approximate = dayOfYear + ((12 - lngHour) / 24)
        let meanAnomaly = (0.9856 * approximate) - 3.289
        var trueLongitude = meanAnomaly
            + (1.916 * sin(degrees: meanAnomaly))
            + (0.020 * sin(degrees: 2 * meanAnomaly))
            + 282.634
        trueLongitude = wrap(trueLongitude, by: 360)

        let sinDec = 0.39782 * sin(degrees: trueLongitude)
        let cosDec = cos(asin(sinDec))
        let latitudeRadians = latitude.degreesToRadians
        let denominator = cosDec * cos(latitudeRadians)
        if denominator == 0 { return nil }
        return (cos(degrees: zenith) - (sinDec * sin(latitudeRadians))) / denominator
    }

    /// Returns true if the sun remains below the horizon (-0.833°) for the entire day (polar night).
    static func isPolarNight(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> Bool {
        guard let cosHour = solarNoonCosHour(on: date, latitude: latitude, longitude: longitude, timeZone: timeZone) else { return false }
        return cosHour > 1
    }

    /// Returns true if the sun remains above the horizon (-0.833°) for the entire day (polar day / midnight sun).
    static func isPolarDay(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> Bool {
        guard let cosHour = solarNoonCosHour(on: date, latitude: latitude, longitude: longitude, timeZone: timeZone) else { return false }
        return cosHour < -1
    }

    /// NOAA sunrise/sunset. Returns nil when the sun does not cross the horizon.
    static func sunriseSunset(
        on date: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> (sunrise: Date, sunset: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }

        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: midnight) ?? day)
        let lngHour = longitude / 15
        let zenith = 90.833

        func localHours(rising: Bool) -> Double? {
            let approximate = rising
                ? dayOfYear + ((6 - lngHour) / 24)
                : dayOfYear + ((18 - lngHour) / 24)
            let meanAnomaly = (0.9856 * approximate) - 3.289
            var trueLongitude = meanAnomaly
                + (1.916 * sin(degrees: meanAnomaly))
                + (0.020 * sin(degrees: 2 * meanAnomaly))
                + 282.634
            trueLongitude = wrap(trueLongitude, by: 360)

            var rightAscension = atan(0.91764 * tan(degrees: trueLongitude)).radiansToDegrees
            rightAscension = wrap(rightAscension, by: 360)
            let longitudeQuadrant = floor(trueLongitude / 90) * 90
            let ascensionQuadrant = floor(rightAscension / 90) * 90
            rightAscension = (rightAscension + (longitudeQuadrant - ascensionQuadrant)) / 15

            let sinDec = 0.39782 * sin(degrees: trueLongitude)
            let cosDec = cos(asin(sinDec))
            let latitudeRadians = latitude.degreesToRadians
            let cosHour = (cos(degrees: zenith) - (sinDec * sin(latitudeRadians))) / (cosDec * cos(latitudeRadians))
            if cosHour > 1 || cosHour < -1 { return nil }

            var hourAngle = rising
                ? 360 - acos(cosHour).radiansToDegrees
                : acos(cosHour).radiansToDegrees
            hourAngle /= 15

            let localMean = hourAngle + rightAscension - (0.06571 * approximate) - 6.622
            var universal = localMean - lngHour
            universal = wrap(universal, by: 24)
            let offsetHours = Double(timeZone.secondsFromGMT(for: midnight)) / 3600
            return wrap(universal + offsetHours, by: 24)
        }

        guard let rise = localHours(rising: true), let set = localHours(rising: false) else { return nil }
        return (
            midnight.addingTimeInterval(rise * 3600),
            midnight.addingTimeInterval(set * 3600)
        )
    }

    static func formatRange(start: Int, end: Int) -> String {
        "\(formatMinute(start))–\(formatMinute(end))"
    }

    static func formatMinute(_ minute: Int) -> String {
        let minute = normalizeMinute(minute)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private static func normalizeMinute(_ minute: Int) -> Int {
        let wrapped = minute % (24 * 60)
        return wrapped >= 0 ? wrapped : wrapped + 24 * 60
    }

    private static func wrap(_ value: Double, by period: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: period)
        if result < 0 { result += period }
        return result
    }
}

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
}

private extension FloatingPoint {
    var radiansToDegrees: Self { self * 180 / .pi }
}

private func sin(degrees: Double) -> Double { sin(degrees.degreesToRadians) }
private func cos(degrees: Double) -> Double { cos(degrees.degreesToRadians) }
private func tan(degrees: Double) -> Double { tan(degrees.degreesToRadians) }
