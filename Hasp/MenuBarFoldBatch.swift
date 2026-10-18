import Foundation

/// All preflight plans are built by the caller without changing visibility.
/// Persist every recovery record before any commit. Submit every participant
/// before readback/AX waits, so one slow native renderer cannot gate the next.
enum MenuBarFoldBatch {
    struct Step {
        var stage: () throws -> Void
        var commit: () throws -> Void
        var verify: () throws -> Void
    }
    static func run(_ steps: [Step], confirm: () throws -> Void) throws {
        for step in steps { try step.stage() }
        for step in steps { try step.commit() }
        for step in steps { try step.verify() }
        try confirm()
    }
}
