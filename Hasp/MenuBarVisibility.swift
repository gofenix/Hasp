import Foundation
import CoreFoundation
import Darwin

/// macOS 27's native per-application visibility records. This codec edits
/// only isAllowed; opaque locations, unknown rows and other fields survive.
struct MenuBarVisibilityRecords {
    private var rows: [Any]
    init(data: Data) throws {
        guard let rows = try PropertyListSerialization.propertyList(from: data, format: nil) as? [Any],
              rows.count.isMultiple(of: 2) else { throw MenuBarVisibilityError.format }
        self.rows = rows
        // Reject ambiguous duplicate owners and malformed known values before
        // touching system preferences. Unknown key kinds are preserved.
        var seen = Set<String>()
        for i in stride(from: 0, to: rows.count, by: 2) {
            guard let owner = Self.owner(rows[i]) else { continue }
            guard seen.insert(owner).inserted, let value = rows[i + 1] as? [String: Any],
                  let allowed = value["isAllowed"] as? NSNumber,
                  CFGetTypeID(allowed) == CFBooleanGetTypeID() else { throw MenuBarVisibilityError.format }
        }
    }
    private static func owner(_ row: Any) -> String? {
        ((row as? [String: Any])?["bundle"] as? [String: Any])?["_0"] as? String
    }
    var states: [String: Bool] {
        var result: [String: Bool] = [:]
        for i in stride(from: 0, to: rows.count, by: 2) {
            if let owner = Self.owner(rows[i]), let value = rows[i + 1] as? [String: Any], let allowed = value["isAllowed"] as? Bool {
                result[owner] = allowed
            }
        }
        return result
    }
    /// Bundle identifiers only; no unrelated preference values or app content.
    var diagnosticRows: [[String: Any]] {
        stride(from: 0, to: rows.count, by: 2).compactMap { i in
            guard let owner = Self.owner(rows[i]), let value = rows[i + 1] as? [String: Any] else { return nil }
            let locations = (value["menuItemLocations"] as? [Any] ?? []).compactMap(Self.owner)
            return ["owner": owner, "allowed": value["isAllowed"] as? Bool ?? true,
                    "itemOwners": locations, "locationOwner": Self.owner(value["location"] as Any) ?? ""]
        }
    }
    /// AX reports the process rendering an item, while Control Center may
    /// store its switch under the enclosing application. Resolve the native
    /// relationship instead of inventing an ineffective helper-app switch.
    /// Multiple records can reference the same item; all must be considered.
    func controllingOwners(for requested: Set<String>) throws -> Set<String> {
        let items = requested.filter(MenuBarVisibilityTransaction.mayHide)
        guard !items.isEmpty else { return [] }
        var found = Set<String>(), controls = Set<String>()
        for i in stride(from: 0, to: rows.count, by: 2) {
            guard let owner = Self.owner(rows[i]), let value = rows[i + 1] as? [String: Any] else { continue }
            let associated = Set((value["menuItemLocations"] as? [Any] ?? []).compactMap(Self.owner))
            let matches = items.intersection(associated.union([owner]))
            guard !matches.isEmpty else { continue }
            // Never hide Hasp through a parent's record, or hide an unrelated
            // sibling just because it shares a record with a requested item.
            guard MenuBarVisibilityTransaction.mayHide(owner),
                  associated.allSatisfy({ MenuBarVisibilityTransaction.mayHide($0) && items.contains($0) }) else {
                throw MenuBarVisibilityError.sharedOwner
            }
            found.formUnion(matches)
            controls.insert(owner)
        }
        guard found == items else { throw MenuBarVisibilityError.unmappedOwner }
        return controls
    }
    func changing(_ changes: [String: Bool]) throws -> Data {
        var next = rows
        var missing = changes
        for i in stride(from: 0, to: next.count, by: 2) {
            guard let owner = Self.owner(next[i]), let allowed = missing.removeValue(forKey: owner),
                  var value = next[i + 1] as? [String: Any] else { continue }
            value["isAllowed"] = allowed
            next[i + 1] = value
        }
        for owner in missing.keys.sorted() {
            let key: [String: Any] = ["bundle": ["_0": owner]]
            next += [key, ["isAllowed": missing[owner]!, "location": key, "menuItemLocations": [key]] as [String: Any]]
        }
        return try PropertyListSerialization.data(fromPropertyList: next, format: .binary, options: 0)
    }
}

enum MenuBarVisibilityError: LocalizedError {
    case access, format, save, command, confirmation, layout, unreadableLayout, rollback, unmappedOwner, sharedOwner
    var errorDescription: String? {
        switch self {
        case .access: return "需要允许 Hasp 访问菜单栏配置。请在「设置 → 权限 → 菜单栏配置访问」中打开完整磁盘访问设置，添加并启用 Hasp。"
        case .format: return "当前系统的菜单栏配置格式尚未适配，未继续修改。"
        case .save: return "无法保存折叠恢复记录，未开始隐藏图标。"
        case .command: return "系统未能更新菜单栏设置，请稍后重试。"
        case .confirmation: return "系统没有确认菜单栏设置更新，已尝试恢复。"
        case .layout: return "系统设置已更新，但图标仍可见，已恢复原状。"
        case .unreadableLayout: return "无法确认实际折叠效果，请检查辅助功能权限。已尝试恢复。"
        case .rollback: return "图标恢复尚未完成。请恢复菜单栏配置访问权限，再关闭折叠；恢复记录已保留。"
        case .unmappedOwner: return "未能匹配部分图标的系统显示开关，未开始折叠。请刷新状态栏名单后重试。"
        case .sharedOwner: return "部分图标与 Hasp 或名单外的图标共用系统显示开关，无法单独折叠，未继续修改。"
        }
    }
}

protocol MenuBarVisibilityStorage: AnyObject {
    func read() throws -> Data
    func write(_ records: Data) throws
    func journal() throws -> [String: Bool]
    func saveJournal(_ originals: [String: Bool]) throws
}

/// A serial worker owns this transaction. A durable journal precedes any hide,
/// and restoration merges only our changes into the latest native records.
final class MenuBarVisibilityTransaction {
    private let storage: MenuBarVisibilityStorage
    init(storage: MenuBarVisibilityStorage) { self.storage = storage }
    static func mayHide(_ owner: String) -> Bool {
        !owner.isEmpty && owner != "app.hasp.menu" && !owner.hasPrefix("app.hasp.menu.") && !owner.hasPrefix("com.apple.")
    }

    struct PreparedFold {
        let records: MenuBarVisibilityRecords
        let originals: [String: Bool]
        let controls: Set<String>
        var desired: [String: Bool] { originals.mapValues { _ in false } }
    }

    func prepare(owners: Set<String>) throws -> PreparedFold {
        let records = try MenuBarVisibilityRecords(data: storage.read())
        var originals = try storage.journal()
        let states = records.states
        let controls = try records.controllingOwners(for: owners)
        for owner in controls where originals[owner] == nil && states[owner] == true {
            originals[owner] = true
        }
        return PreparedFold(records: records, originals: originals, controls: controls)
    }
    func stage(_ plan: PreparedFold) throws {
        guard !plan.originals.isEmpty else { return }
        do { try storage.saveJournal(plan.originals) } catch { throw MenuBarVisibilityError.save }
    }
    func commit(_ plan: PreparedFold) throws {
        let desired = plan.desired
        if desired.contains(where: { plan.records.states[$0.key] != $0.value }) {
            try storage.write(plan.records.changing(desired))
        }
    }
    func verify(_ plan: PreparedFold) throws {
        guard !plan.desired.isEmpty else { return }
        let actual = try MenuBarVisibilityRecords(data: storage.read()).states
        guard plan.desired.allSatisfy({ actual[$0.key] == $0.value }) else { throw MenuBarVisibilityError.confirmation }
    }

    func fold(owners: Set<String>, confirm: () -> Bool?) throws {
        let plan = try prepare(owners: owners)
        guard !plan.controls.isEmpty else { return }
        try stage(plan)
        do {
            try commit(plan)
            try verify(plan)
            switch confirm() {
            case true?: return
            case false?: throw MenuBarVisibilityError.layout
            case nil: throw MenuBarVisibilityError.unreadableLayout
            }
        } catch {
            let failure = error
            do { try restore() } catch { throw MenuBarVisibilityError.rollback }
            throw failure
        }
    }

    func restore() throws {
        let originals = try storage.journal()
        guard !originals.isEmpty else { return } // OFF needs no permission if nothing was hidden.
        let records = try MenuBarVisibilityRecords(data: storage.read())
        let changes = originals.filter { records.states[$0.key] != $0.value }
        if !changes.isEmpty { try storage.write(records.changing(changes)) }
        let actual = try MenuBarVisibilityRecords(data: storage.read()).states
        guard originals.allSatisfy({ actual[$0.key] == $0.value }) else { throw MenuBarVisibilityError.rollback }
        try storage.saveJournal([:])
    }
}

final class NativeMenuBarVisibilityStorage: MenuBarVisibilityStorage {
    // Production must use an explicit container/domain. Absolute preference
    // paths can fall back to a local cache after the daemon rejects them and
    // falsely read back our write without changing the actual menu bar.
    // Other transports remain explicit diagnostic/reproduction options only.
    enum Transport { case command, direct, container, suiteRefresh }
    static let configuration = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist")
    private let configurationURL: URL
    private let folder: URL
    private let transport: Transport
    init(configuration: URL = NativeMenuBarVisibilityStorage.configuration, folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Hasp/MenuBar"), transport: Transport = .container) {
        precondition(transport != .container || configuration == Self.configuration, "An isolated test domain must select a non-container transport")
        configurationURL = configuration
        self.folder = folder
        self.transport = transport
    }
    private var journalURL: URL { folder.appendingPathComponent("visibility-restore-v1.json") }

    func read() throws -> Data {
        // A preferences export can silently produce an empty domain on access
        // denial. Establish real file access first; never import an empty one.
        do { _ = try Data(contentsOf: configurationURL) }
        catch { throw MenuBarVisibilityError.access }
        if transport == .direct || transport == .suiteRefresh {
            let domain = configurationURL.deletingPathExtension().path as CFString
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
                  let records = CFPreferencesCopyValue("trackedApplications" as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data else {
                throw MenuBarVisibilityError.command
            }
            _ = try MenuBarVisibilityRecords(data: records)
            return records
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let export = folder.appendingPathComponent("read-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: export) }
        let arguments = transport == .container
            ? ["-container", "group.com.apple.controlcenter", "export", "group.com.apple.controlcenter", export.path]
            : ["export", configurationURL.deletingPathExtension().path, export.path]
        try command(arguments)
        guard let outer = try PropertyListSerialization.propertyList(from: Data(contentsOf: export), format: nil) as? [String: Any],
              let records = outer["trackedApplications"] as? Data else { throw MenuBarVisibilityError.format }
        _ = try MenuBarVisibilityRecords(data: records)
        return records
    }

    func write(_ records: Data) throws {
        _ = try MenuBarVisibilityRecords(data: records)
        guard records.count <= 48 * 1024 else { throw MenuBarVisibilityError.format }
        if transport == .direct || transport == .suiteRefresh {
            let domain = configurationURL.deletingPathExtension().path as CFString
            CFPreferencesSetValue("trackedApplications" as CFString, records as CFData, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw MenuBarVisibilityError.command }
            if transport == .suiteRefresh { _ = CFPreferencesAppSynchronize("group.com.apple.controlcenter" as CFString) }
            return
        }
        // A one-key import takes defaults' batch refresh path, which is used by
        // the native visibility transport. Import merges the supplied keys;
        // never re-import a stale snapshot of the entire system domain.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let update = folder.appendingPathComponent("update-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: update) }
        try PropertyListSerialization.data(fromPropertyList: ["trackedApplications": records], format: .binary, options: 0)
            .write(to: update, options: .atomic)
        let arguments = transport == .container
            ? ["-container", "group.com.apple.controlcenter", "import", "group.com.apple.controlcenter", update.path]
            : ["import", configurationURL.deletingPathExtension().path, update.path]
        try command(arguments)
    }

    private func command(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw MenuBarVisibilityError.command
        }
        guard process.terminationStatus == 0 else { throw MenuBarVisibilityError.command }
    }

    func journal() throws -> [String: Bool] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [:] }
        let result = try JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: journalURL))
        guard result.allSatisfy({ MenuBarVisibilityTransaction.mayHide($0.key) && $0.value }) else { throw MenuBarVisibilityError.format }
        return result
    }
    func saveJournal(_ originals: [String: Bool]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(originals).write(to: journalURL, options: .atomic)
    }
    func saveAttempt(_ report: [String: Any]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        try? data.write(to: folder.appendingPathComponent("last-fold-attempt.json"), options: .atomic)
    }
    func lastAttempt() -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("last-fold-attempt.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    func inspectDirectTransport() -> [String: Any] {
        let path = configurationURL.deletingPathExtension().path as CFString
        let synchronized = CFPreferencesSynchronize(path, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let direct = CFPreferencesCopyValue("trackedApplications" as CFString, path, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data
        let disk = (try? PropertyListSerialization.propertyList(from: Data(contentsOf: configurationURL), format: nil)) as? [String: Any]
        return ["directPreferencesReadable": direct != nil, "directSynchronizes": synchronized,
                "avoidsPreferencesDaemon": ProcessInfo.processInfo.environment["__CFPREFERENCES_AVOID_DAEMON"] ?? "unset",
                "directPreferencesMatchesFile": direct != nil && direct == disk?["trackedApplications"] as? Data,
                "directRecordCount": direct.flatMap { try? MenuBarVisibilityRecords(data: $0).states.count } ?? -1]
    }
}
