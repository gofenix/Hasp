import Foundation

final class SystemVisibilityFixture: SystemMenuPreferenceStorage {
    var values: [SystemMenuVisibility.Item: NSNumber] = [.input: true]
    var writes = 0
    var deny = false
    var ignore = false
    var beforeWrite: (() throws -> Void)?
    func value(_ item: SystemMenuVisibility.Item) -> Any? { values[item] }
    func write(_ item: SystemMenuVisibility.Item, _ value: Any?) throws {
        try beforeWrite?()
        if deny { throw MenuBarVisibilityError.command }
        writes += 1
        if !ignore { values[item] = value as? NSNumber }
    }
}

@main enum SystemMenuVisibilityTests {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let fixture = SystemVisibilityFixture()
        let system = SystemMenuVisibility(folder: folder, preferences: fixture)
        let initial = try system.snapshot()
        let owners: Set<String> = ["com.apple.TextInputMenuAgent", "com.apple.campo"]
        fixture.beforeWrite = { precondition(try! system.journal().count == 2, "Journal must precede every hide") }
        try system.fold(owners: owners)
        precondition(fixture.values[.input] == false && fixture.values[.search] == true)
        precondition(fixture.writes == 2)
        try system.fold(owners: owners)
        precondition(fixture.writes == 2, "Do not rewrite unchanged settings on refresh")
        fixture.beforeWrite = nil
        // A new instance must recover exact originals, including an absent
        // per-host Spotlight key rather than leaving an explicit false value.
        try SystemMenuVisibility(folder: folder, preferences: fixture).restore()
        precondition(try! system.snapshot() == initial)
        precondition(fixture.values[.search] == nil && fixture.values[.input] == true)
        precondition(try! system.journal().isEmpty)
        let untouched = fixture.writes
        try system.restore()
        try system.fold(owners: ["app.hasp.menu", "com.apple.controlcenter", "com.apple.finder"])
        precondition(fixture.writes == untouched, "Never toggle unrelated Apple services")
        fixture.values[.input] = false; fixture.values[.search] = true
        try system.fold(owners: owners)
        try system.restore()
        precondition(fixture.values[.input] == false && fixture.values[.search] == true, "Preserve user-hidden items")
        fixture.values[.input] = true; fixture.values[.search] = nil
        try system.fold(owners: owners)
        fixture.deny = true
        do { try system.restore(); preconditionFailure() } catch {}
        precondition(try! system.journal().count == 2, "Retain recovery after failure")
        fixture.deny = false
        try system.restore()
        fixture.ignore = true
        do { try system.fold(owners: owners); preconditionFailure() } catch {}
        precondition(try! system.journal().count == 2, "Readback failure must retain originals")
        fixture.ignore = false
        try system.restore()
        precondition(SystemMenuVisibility.manages("com.apple.Spotlight"))
        precondition(!SystemMenuVisibility.isFoldTarget("com.apple.controlcenter"))
        precondition(!SystemMenuVisibility.isFoldTarget("app.hasp.menu"))
        print("System menu visibility: restore absence, crash recovery, failures, no-op and protected owners passed")
    }
}
