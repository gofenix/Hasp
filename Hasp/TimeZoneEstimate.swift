import Foundation

struct TimeZoneEstimate {
    static func coordinate(timeZone: TimeZone = .current) -> (latitude: Double, longitude: Double) {
        if let known = cities[timeZone.identifier] {
            return known
        }
        let longitude = Double(timeZone.secondsFromGMT()) / 240
        return (35, longitude)
    }

    private static let cities: [String: (Double, Double)] = [
        "Asia/Shanghai": (31.23, 121.47),
        "Asia/Chongqing": (29.56, 106.55),
        "Asia/Harbin": (45.75, 126.65),
        "Asia/Urumqi": (43.83, 87.62),
        "Asia/Hong_Kong": (22.32, 114.17),
        "Asia/Taipei": (25.03, 121.57),
        "Asia/Tokyo": (35.68, 139.69),
        "Asia/Singapore": (1.35, 103.82),
        "Europe/London": (51.51, -0.13),
        "America/Los_Angeles": (34.05, -118.24),
        "America/New_York": (40.71, -74.01)
    ]
}
