import Foundation

final class VisibilityFixture: MenuBarVisibilityStorage {
    var data: Data
    var originals: [String: Bool] = [:]
    var writes = 0
    var readDenied = false
    var saveDenied = false
    var writeFailures = 0
    var ignoreWrite = false
    init(_ data: Data) { self.data = data }
    func read() throws -> Data {
        if readDenied { throw MenuBarVisibilityError.access }
        return data
    }
    func write(_ records: Data) throws {
        writes += 1
        if writeFailures > 0 { writeFailures -= 1; throw MenuBarVisibilityError.command }
        if !ignoreWrite { data = records }
    }
    func journal() throws -> [String: Bool] { originals }
    func saveJournal(_ value: [String: Bool]) throws {
        if saveDenied { throw MenuBarVisibilityError.save }
        originals = value
    }
    var states: [String: Bool] { try! MenuBarVisibilityRecords(data: data).states }
}

@main enum MenuBarVisibilityTests {
    static func pack(_ value: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) }
    static func key(_ owner: String) -> [String: Any] { ["bundle": ["_0": owner]] }
    static func fails(_ body: () throws -> Void, _ error: MenuBarVisibilityError) {
        do { try body(); preconditionFailure("Expected \(error)") }
        catch let actual as MenuBarVisibilityError { precondition(String(describing: actual) == String(describing: error)) }
        catch { preconditionFailure("Unexpected \(error)") }
    }
    static func main() throws {
        let rows: [Any] = [key("com.example.magpie"), ["isAllowed": true, "location": ["unknown": 6], "extra": "preserve"],
                           key("com.example.lark"), ["isAllowed": true],
                           key("com.example.user-hidden"), ["isAllowed": false],
                           ["future-kind": "opaque"], ["private-field": Data([1, 2, 3])]]
        let initial = try pack(rows)
        let codec = try MenuBarVisibilityRecords(data: initial)
        precondition(codec.states.count == 3 && codec.states["com.example.user-hidden"] == false)
        let changed = try codec.changing(["com.example.magpie": false, "com.example.new": false])
        let decoded = try PropertyListSerialization.propertyList(from: changed, format: nil) as! [Any]
        precondition((decoded[1] as! [String: Any])["extra"] as? String == "preserve")
        precondition((decoded[1] as! [String: Any])["location"] as! NSDictionary == ["unknown": 6] as NSDictionary)
        precondition(decoded[6] as! NSDictionary == rows[6] as! NSDictionary && decoded[7] as! NSDictionary == rows[7] as! NSDictionary)
        let changedStates = try MenuBarVisibilityRecords(data: changed).states
        precondition(changedStates["com.example.new"] == false)
        fails({ _ = try MenuBarVisibilityRecords(data: pack([key("x")])) }, .format)
        fails({ _ = try MenuBarVisibilityRecords(data: pack([key("x"), ["isAllowed": 1]])) }, .format)
        fails({ _ = try MenuBarVisibilityRecords(data: pack([key("x"), ["isAllowed": true], key("x"), ["isAllowed": false]])) }, .format)
        fails({ _ = try MenuBarVisibilityRecords(data: pack([key("x"), ["future": true]])) }, .format)

        let fixture = VisibilityFixture(initial)
        let engine = MenuBarVisibilityTransaction(storage: fixture)
        let owners: Set<String> = ["com.example.magpie", "com.example.lark", "com.example.user-hidden", "app.hasp.menu", "com.apple.controlcenter"]
        try engine.fold(owners: owners) {
            precondition(fixture.originals == ["com.example.magpie": true, "com.example.lark": true], "Save original state before hiding")
            precondition(fixture.states["com.example.magpie"] == false && fixture.states["com.example.lark"] == false)
            return true
        }
        precondition(fixture.writes == 1)
        try engine.fold(owners: owners, confirm: { true })
        precondition(fixture.writes == 1, "An unchanged fold must not rewrite native settings")
        // A concurrent unrelated native preference edit must survive restoration.
        fixture.data = try MenuBarVisibilityRecords(data: fixture.data).changing(["com.example.other": false])
        try MenuBarVisibilityTransaction(storage: fixture).restore() // Simulate relaunch/crash recovery.
        precondition(fixture.originals.isEmpty && fixture.states["com.example.magpie"] == true && fixture.states["com.example.lark"] == true)
        precondition(fixture.states["com.example.user-hidden"] == false && fixture.states["com.example.other"] == false)

        fixture.readDenied = true
        let writes = fixture.writes
        try engine.restore() // Nothing owned: OFF requires no protected read.
        fails({ try engine.fold(owners: owners, confirm: { preconditionFailure("Cannot confirm without access") }) }, .access)
        precondition(fixture.writes == writes && fixture.originals.isEmpty)
        fixture.readDenied = false; fixture.saveDenied = true
        fails({ try engine.fold(owners: owners, confirm: { true }) }, .save)
        precondition(fixture.writes == writes)
        fixture.saveDenied = false; fixture.writeFailures = 1
        fails({ try engine.fold(owners: owners, confirm: { true }) }, .command)
        precondition(fixture.originals.isEmpty && fixture.states["com.example.magpie"] == true)
        fixture.ignoreWrite = true
        fails({ try engine.fold(owners: owners, confirm: { preconditionFailure("Readback must precede AX confirmation") }) }, .confirmation)
        precondition(fixture.originals.isEmpty)
        fixture.ignoreWrite = false
        fails({ try engine.fold(owners: owners, confirm: { false }) }, .layout)
        precondition(fixture.states["com.example.magpie"] == true && fixture.originals.isEmpty)
        fails({ try engine.fold(owners: owners, confirm: { nil }) }, .unreadableLayout)
        precondition(fixture.states["com.example.lark"] == true && fixture.originals.isEmpty)

        fails({ try engine.fold(owners: owners, confirm: {
            fixture.writeFailures = 1
            return false
        }) }, .rollback)
        precondition(!fixture.originals.isEmpty && fixture.states["com.example.magpie"] == false, "Do not delete recovery records when restoring fails")
        try engine.restore()
        precondition(fixture.originals.isEmpty && fixture.states["com.example.magpie"] == true)
        let unknownWrites = fixture.writes
        fails({ try engine.fold(owners: ["com.example.untracked"], confirm: { preconditionFailure() }) }, .unmappedOwner)
        precondition(fixture.writes == unknownWrites && fixture.originals.isEmpty, "Do not invent untracked switches")
        fixture.data = try MenuBarVisibilityRecords(data: fixture.data).changing(["com.example.new": true])
        try engine.fold(owners: ["com.example.new"], confirm: { true })
        precondition(fixture.states["com.example.new"] == false)
        try engine.restore()
        precondition(fixture.states["com.example.new"] == true)
        let before = fixture.writes
        try engine.fold(owners: ["app.hasp.menu", "app.hasp.menu.helper", "com.apple.inputmethod"], confirm: { preconditionFailure() })
        precondition(fixture.writes == before && fixture.originals.isEmpty)

        // Real-device relationships: AX item owner != native preference key.
        // The old backend appended helper records, leaving these main switches
        // enabled. Its all-item confirmation then rolled the whole fold back.
        let pairs = [("com.electron.lark", "com.electron.lark.helper"),
                     ("com.microsoft.wdav", "com.microsoft.wdav.tray"),
                     ("com.work.pc.doubao", "com.work.pc.doubao.browser")]
        var helperRows: [Any] = []
        for (parent, helper) in pairs {
            helperRows += [key(parent), ["isAllowed": true, "location": key(parent), "menuItemLocations": [key(helper)], "opaque": "preserved"]]
            // Preserve and include duplicate references left by earlier versions.
            helperRows += [key(helper), ["isAllowed": true, "menuItemLocations": [key(helper)]]]
        }
        helperRows += [key("com.example.hidden"), ["isAllowed": false, "menuItemLocations": [key("com.example.hidden.helper")]]]
        let helperFixture = VisibilityFixture(try pack(helperRows))
        let helperEngine = MenuBarVisibilityTransaction(storage: helperFixture)
        let helperOwners = Set(pairs.map { $0.1 }).union(["com.example.hidden.helper"])
        let expectedControls = Set(pairs.flatMap { [$0.0, $0.1] }).union(["com.example.hidden"])
        let mapped = try MenuBarVisibilityRecords(data: helperFixture.data).controllingOwners(for: helperOwners)
        precondition(mapped == expectedControls)
        try helperEngine.fold(owners: helperOwners) {
            precondition(pairs.allSatisfy { helperFixture.states[$0.0] == false && helperFixture.states[$0.1] == false })
            precondition(helperFixture.originals.count == 6 && helperFixture.originals["com.example.hidden"] == nil)
            return true
        }
        precondition(helperFixture.states.count == 7, "Resolution must not append new native records")
        try helperEngine.restore()
        precondition(pairs.allSatisfy { helperFixture.states[$0.0] == true && helperFixture.states[$0.1] == true })
        precondition(helperFixture.states["com.example.hidden"] == false && helperFixture.originals.isEmpty)
        let protected = VisibilityFixture(try pack([key("ai.example.launcher"), ["isAllowed": true,
            "menuItemLocations": [key("app.hasp.menu"), key("com.example.helper")]]]))
        fails({ try MenuBarVisibilityTransaction(storage: protected).fold(owners: ["com.example.helper"], confirm: { true }) }, .sharedOwner)
        precondition(protected.writes == 0 && protected.originals.isEmpty, "A parent must never hide Hasp indirectly")
        let shared = VisibilityFixture(try pack([key("com.example.parent"), ["isAllowed": true,
            "menuItemLocations": [key("com.example.a"), key("com.example.b")]]]))
        fails({ try MenuBarVisibilityTransaction(storage: shared).fold(owners: ["com.example.a"], confirm: { true }) }, .sharedOwner)
        precondition(shared.writes == 0 && shared.originals.isEmpty, "Do not hide an unrelated sibling")
        try MenuBarVisibilityTransaction(storage: shared).fold(owners: ["com.example.a", "com.example.b"], confirm: { true })
        precondition(shared.originals == ["com.example.parent": true])
        try MenuBarVisibilityTransaction(storage: shared).restore()
        // macOS can retain both parent and helper locations while AX reports
        // just one. Reproduce all three real-device rows from the failure.
        var mixedRows: [Any] = []
        var applications: [String: String] = [:]
        for (parent, helper) in pairs {
            mixedRows += [key(parent), ["isAllowed": true, "menuItemLocations": [key(helper), key(parent)], "extra": "keep"]]
            mixedRows += [key(helper), ["isAllowed": true, "menuItemLocations": [key(helper)]]]
            applications[parent] = "/Applications/\(parent).app"
            applications[helper] = applications[parent]
        }
        mixedRows += [key("app.hasp.menu"), ["isAllowed": true], key("com.example.unrelated"), ["isAllowed": true]]
        let mixed = VisibilityFixture(try pack(mixedRows))
        let mixedEngine = MenuBarVisibilityTransaction(storage: mixed)
        let onePerApplication: Set<String> = [pairs[0].1, pairs[1].1, pairs[2].0]
        fails({ _ = try MenuBarVisibilityRecords(data: mixed.data).controllingOwners(for: onePerApplication) }, .sharedOwner)
        try mixedEngine.fold(owners: onePerApplication, applicationIdentity: { applications[$0] }) {
            precondition(pairs.allSatisfy { mixed.states[$0.0] == false && mixed.states[$0.1] == false })
            precondition(mixed.states["app.hasp.menu"] == true && mixed.states["com.example.unrelated"] == true)
            return true
        }
        precondition(mixed.originals.count == 6)
        try mixedEngine.restore()
        precondition(mixed.states.values.allSatisfy { $0 } && mixed.originals.isEmpty)
        let preserved = try PropertyListSerialization.propertyList(from: mixed.data, format: nil) as! [Any]
        precondition((preserved[1] as! [String: Any])["extra"] as? String == "keep")
        // A matching prefix does not establish containment. Real cross-app
        // sharing must still fail without writes, even when aliases resolve.
        let independent: [String: String] = ["com.example.parent": "/Applications/A.app", "com.example.a": "/Applications/A.app",
                                            "com.example.b": "/Applications/B.app"]
        let sharedWrites = shared.writes
        fails({ try MenuBarVisibilityTransaction(storage: shared).fold(owners: ["com.example.a"], applicationIdentity: { independent[$0] }, confirm: { true }) }, .sharedOwner)
        precondition(shared.writes == sharedWrites && shared.originals.isEmpty)
        fails({ try MenuBarVisibilityTransaction(storage: protected).fold(owners: ["com.example.helper"], applicationIdentity: { _ in "/Applications/Launcher.app" }, confirm: { true }) }, .sharedOwner)
        precondition(protected.writes == 0 && protected.originals.isEmpty)
        let inconsistent = VisibilityFixture(try pack([key("com.example.a"), ["isAllowed": false]]))
        fails({ try MenuBarVisibilityTransaction(storage: inconsistent).fold(owners: ["com.example.a"], confirm: { false }) }, .layout)
        precondition(inconsistent.writes == 0 && inconsistent.originals.isEmpty, "Disabled flags alone cannot prove hiding")
        // Exercise the real defaults transport only in an isolated task-local
        // domain. Importing one key must merge rather than clear other keys.
        let transportFolder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "verification/menu-visibility-transport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: transportFolder, withIntermediateDirectories: true)
        let config = transportFolder.appendingPathComponent("app.hasp.transport-test.plist")
        let untouched: [String: Any] = ["opaque": ["nested": [1, 2, 3]], "anotherKey": "preserve"]
        var outer = untouched
        outer["trackedApplications"] = initial
        try pack(outer).write(to: config)
        let transport = NativeMenuBarVisibilityStorage(configuration: config, folder: transportFolder.appendingPathComponent("support"), transport: .command)
        let transportBefore = try transport.read()
        let transportAfter = try MenuBarVisibilityRecords(data: transportBefore).changing(["com.example.magpie": false])
        try transport.write(transportAfter)
        let imported = try transport.read()
        precondition(try! MenuBarVisibilityRecords(data: imported).states["com.example.magpie"] == false)
        let output = try PropertyListSerialization.propertyList(from: Data(contentsOf: config), format: nil) as! [String: Any]
        precondition(output["opaque"] as! NSDictionary == untouched["opaque"] as! NSDictionary)
        precondition(output["anotherKey"] as? String == "preserve")
        let files = try FileManager.default.contentsOfDirectory(atPath: transportFolder.appendingPathComponent("support").path)
        precondition(files.isEmpty, "Temporary import/export files must be cleaned")
        let direct = NativeMenuBarVisibilityStorage(configuration: config, folder: transportFolder.appendingPathComponent("direct-support"), transport: .direct)
        let directBefore = try MenuBarVisibilityRecords(data: direct.read())
        precondition(directBefore.states["com.example.magpie"] == false)
        try direct.write(directBefore.changing(["com.example.magpie": true]))
        let directAfter = try MenuBarVisibilityRecords(data: direct.read())
        precondition(directAfter.states["com.example.magpie"] == true)
        let final = try PropertyListSerialization.propertyList(from: Data(contentsOf: config), format: nil) as! [String: Any]
        precondition(final["opaque"] as! NSDictionary == untouched["opaque"] as! NSDictionary)
        precondition(final["anotherKey"] as? String == "preserve")
        precondition(MenuBarVisibilityError.access.opensPermissions
                     && MenuBarVisibilityError.unreadableLayout.opensPermissions
                     && MenuBarVisibilityError.rollback.opensPermissions)
        precondition(!MenuBarVisibilityError.sharedOwner.opensPermissions
                     && !MenuBarVisibilityError.unmappedOwner.opensPermissions
                     && !MenuBarVisibilityError.layout.opensPermissions)
        print("PASS: isolated defaults import/readback preserves unrelated keys; helper-to-parent and duplicate ownership; protected/shared groups; unknown owners; codec, user choices, recovery and failure rollback")
    }
}
