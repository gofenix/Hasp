import Foundation

@main enum MenuBarFoldBatchTests {
    enum Failure: Error { case stage, commit, readback }
    static func main() throws {
        var events: [String] = []
        var failStage: Int?, failCommit: Int?, failVerify: Int?
        func steps() -> [MenuBarFoldBatch.Step] {
            (0..<3).map { index in
                .init(stage: { events.append("stage\(index)"); if failStage == index { throw Failure.stage } },
                      commit: { events.append("commit\(index)"); if failCommit == index { throw Failure.commit } },
                      verify: { events.append("verify\(index)"); if failVerify == index { throw Failure.readback } })
            }
        }
        try MenuBarFoldBatch.run(steps()) { events.append("AX") }
        precondition(events == ["stage0", "stage1", "stage2", "commit0", "commit1", "commit2", "verify0", "verify1", "verify2", "AX"],
                     "All recovery records precede changes; no readback/AX barrier may split submissions")
        events = []; failStage = 1
        do { try MenuBarFoldBatch.run(steps()) { preconditionFailure() }; preconditionFailure() } catch {}
        precondition(events == ["stage0", "stage1"], "A journal failure must leave native visibility untouched")
        events = []; failStage = nil; failCommit = 1
        do { try MenuBarFoldBatch.run(steps()) { preconditionFailure() }; preconditionFailure() } catch {}
        precondition(events == ["stage0", "stage1", "stage2", "commit0", "commit1"], "Partial write failure must reach caller rollback without claiming confirmation")
        events = []; failCommit = nil; failVerify = 0
        do { try MenuBarFoldBatch.run(steps()) { preconditionFailure() }; preconditionFailure() } catch {}
        precondition(events == ["stage0", "stage1", "stage2", "commit0", "commit1", "commit2", "verify0"])
        print("Fold batch passed: all journals before changes, continuous submission, one confirmation, failure barriers")
    }
}
