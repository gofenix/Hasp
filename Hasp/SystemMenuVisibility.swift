import Foundation

protocol SystemMenuPreferenceStorage {
    func value(_ item: SystemMenuVisibility.Item) -> Any?
    func write(_ item: SystemMenuVisibility.Item, _ value: Any?) throws
}

struct NativeSystemMenuPreferences: SystemMenuPreferenceStorage {
    func value(_ item: SystemMenuVisibility.Item) -> Any? {
        CFPreferencesSynchronize(item.domain as CFString, kCFPreferencesCurrentUser,
                                 item.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(item.key as CFString, item.domain as CFString, kCFPreferencesCurrentUser,
                                      item.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost)
    }
    func write(_ item: SystemMenuVisibility.Item, _ value: Any?) throws {
        let host = item.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        CFPreferencesSetValue(item.key as CFString, value as CFPropertyList?, item.domain as CFString, kCFPreferencesCurrentUser, host)
        guard CFPreferencesSynchronize(item.domain as CFString, kCFPreferencesCurrentUser, host) else { throw MenuBarVisibilityError.command }
    }
}

/// System-owned status items do not have trackedApplications bundle switches.
/// Only their menu visibility preferences are changed, never input sources,
/// search shortcuts, running services or search indexes.
final class SystemMenuVisibility {
    enum Item: String, Codable, CaseIterable {
        case input, search
        var owner: String { self == .input ? "com.apple.TextInputMenuAgent" : "com.apple.campo" }
        var owners: Set<String> { self == .input ? [owner] : [owner, "com.apple.Spotlight"] }
        var domain: String { self == .input ? "com.apple.TextInputMenu" : "com.apple.Spotlight" }
        var key: String { self == .input ? "visible" : "MenuItemHidden" }
        var currentHost: Bool { self == .search }
        var hidden: Bool { self == .search }
    }
    struct Original: Codable, Equatable { var item: Item; var value: Data? }
    static func manages(_ owner: String) -> Bool { Item.allCases.contains { $0.owners.contains(owner) } }
    static func isFoldTarget(_ owner: String) -> Bool { MenuBarVisibilityTransaction.mayHide(owner) || manages(owner) }
    private let journalURL: URL
    private let preferences: any SystemMenuPreferenceStorage
    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Hasp/MenuBar"),
         preferences: any SystemMenuPreferenceStorage = NativeSystemMenuPreferences()) {
        journalURL = folder.appendingPathComponent("system-visibility-restore-v1.json")
        self.preferences = preferences
    }
    private func value(_ item: Item) -> Any? {
        preferences.value(item)
    }
    private func write(_ item: Item, _ value: Any?) throws {
        try preferences.write(item, value)
    }
    func snapshot() throws -> [Original] {
        try Item.allCases.map { item in
            Original(item: item, value: try value(item).map {
                try PropertyListSerialization.data(fromPropertyList: ["value": $0], format: .binary, options: 0)
            })
        }
    }
    func journal() throws -> [Original] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
        let originals = try JSONDecoder().decode([Original].self, from: Data(contentsOf: journalURL))
        guard Set(originals.map(\.item)).count == originals.count else { throw MenuBarVisibilityError.format }
        // Validate every original before any restoration writes.
        for original in originals { _ = try decoded(original) }
        return originals
    }
    private func decoded(_ original: Original) throws -> Any? {
        guard let data = original.value else { return nil }
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = dict["value"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() || CFGetTypeID(value) == CFNumberGetTypeID() else {
            throw MenuBarVisibilityError.format
        }
        return value
    }
    struct PreparedFold {
        let originals: [Original]
        let needsSave: Bool
    }
    func prepare(owners: Set<String>) throws -> PreparedFold {
        let previous = try journal()
        var originals = previous
        let existing = Set(originals.map(\.item))
        originals += try snapshot().filter { !$0.item.owners.isDisjoint(with: owners) && !existing.contains($0.item) }
        for original in originals { _ = try decoded(original) }
        return PreparedFold(originals: originals, needsSave: originals != previous)
    }
    func stage(_ plan: PreparedFold) throws {
        if plan.needsSave {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(plan.originals).write(to: journalURL, options: .atomic)
        }
    }
    func commit(_ plan: PreparedFold) throws {
        for original in plan.originals where (value(original.item) as? NSNumber)?.boolValue != original.item.hidden {
            try write(original.item, original.item.hidden)
        }
    }
    func verify(_ plan: PreparedFold) throws {
        guard plan.originals.allSatisfy({ (value($0.item) as? NSNumber)?.boolValue == $0.item.hidden }) else {
            throw MenuBarVisibilityError.confirmation
        }
    }
    func fold(owners: Set<String>) throws {
        let plan = try prepare(owners: owners)
        try stage(plan)
        try commit(plan)
        try verify(plan)
    }
    func restore() throws {
        let originals = try journal()
        guard !originals.isEmpty else { return }
        for original in originals {
            try write(original.item, decoded(original))
        }
        for original in originals {
            let expected = try decoded(original) as? NSNumber
            let actual = value(original.item) as? NSNumber
            guard actual == expected else { throw MenuBarVisibilityError.rollback }
        }
        try FileManager.default.removeItem(at: journalURL)
    }
}
