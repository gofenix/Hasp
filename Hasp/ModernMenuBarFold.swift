import AppKit
import ApplicationServices
import OSLog

struct MenuBarLayoutFailure: ExpressibleByStringLiteral {
    var message: String
    var stillFolded: Bool = false
    init(_ message: String, stillFolded: Bool = false) { self.message = message; self.stillFolded = stillFolded }
    init(stringLiteral value: String) { message = value }
}

/// System preferences and verification run on one worker, in request order.
/// OFF cannot race an earlier slow ON; callbacks remain generation-checked by
/// the model. No simulated input, application activation or status spacers.
final class ModernMenuBarFold: @unchecked Sendable {
    static let shared = ModernMenuBarFold()
    private static let log = Logger(subsystem: "app.hasp.menu", category: "NativeFold")
    private let queue = DispatchQueue(label: "app.hasp.native-menu-visibility", qos: .userInitiated)
    private let storage = NativeMenuBarVisibilityStorage()
    private let cacheLock = NSLock()
    private var cachedIcons: [MenuBarIcon] = []

    func completeIcons(_ live: [MenuBarIcon]) -> [MenuBarIcon] {
        cacheLock.lock(); let cached = cachedIcons; cacheLock.unlock()
        let liveIDs = Set(live.map(\.id))
        return (live + cached.filter {
            !liveIDs.contains($0.id) && $0.target.map { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated == false } == true
        }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor func apply(_ folded: Bool, icons: [MenuBarIcon], completion: @escaping (MenuBarLayoutFailure?) -> Void) {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let strips = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width, height: 40) }
        queue.async { [self] in
            var failure: MenuBarLayoutFailure?
            var attempt: [String: Any] = ["at": Date().timeIntervalSince1970, "transport": "single-key-import"]
            var samples = [[String: Any]]()
            let transaction = MenuBarVisibilityTransaction(storage: storage)
            let system = SystemMenuVisibility()
            func restoreAll() throws {
                var failed = false
                do { try transaction.restore() } catch { failed = true }
                do { try system.restore() } catch { failed = true }
                MenuBarPrefs.show()
                if failed { throw MenuBarVisibilityError.rollback }
            }
            do {
                if folded {
                    guard MenuBarCensus.isTrusted else { throw MenuBarVisibilityError.unreadableLayout }
                    let source = icons.contains(where: { $0.target != nil }) ? icons : MenuBarCensus.thirdPartyIcons()
                    let candidates = source.filter { $0.target != nil && !$0.id.hasPrefix("system.") }
                    let allOwners = Set(candidates.compactMap(\.target?.bundleIdentifier))
                    let owners = allOwners
                        .filter(MenuBarVisibilityTransaction.mayHide)
                    let systemOwners = allOwners.filter(SystemMenuVisibility.manages)
                    attempt["targetCount"] = owners.count + systemOwners.count
                    attempt["systemOwners"] = systemOwners.sorted()
                    cacheLock.lock()
                    let known = Set(cachedIcons.map(\.id))
                    cachedIcons += candidates.filter { !known.contains($0.id) }
                    cacheLock.unlock()
                    let started = DispatchTime.now().uptimeNanoseconds
                    func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000 }
                    let appPlan = try transaction.prepare(owners: Set(owners))
                    let systemPlan = try system.prepare(owners: Set(systemOwners))
                    let modulePlan = try MenuBarPrefs.prepareHide()
                    attempt["prepareMs"] = elapsed()
                    let submitStart = elapsed()
                    try MenuBarFoldBatch.run([
                        .init(stage: { try transaction.stage(appPlan) },
                              commit: { try transaction.commit(appPlan); attempt["appsSubmittedMs"] = elapsed() },
                              verify: { try transaction.verify(appPlan) }),
                        .init(stage: { try system.stage(systemPlan) },
                              commit: { try system.commit(systemPlan); attempt["inputSearchSubmittedMs"] = elapsed() },
                              verify: { try system.verify(systemPlan) }),
                        .init(stage: {}, commit: { MenuBarPrefs.commitHide(modulePlan); attempt["modulesSubmittedMs"] = elapsed() }, verify: {})
                    ]) {
                        let submitted = attempt["modulesSubmittedMs"] as? Double ?? elapsed()
                        attempt["submitMs"] = submitted - submitStart
                        attempt["readbackMs"] = elapsed() - submitted
                        let verifyStart = elapsed()
                        let expected = owners.union(systemOwners)
                        let deadline = Date().addingTimeInterval(3)
                        var hidden: Bool?
                        repeat {
                            if let visible = MenuBarCensus.nativeRenderedOwners(strips: strips) {
                                let remaining = expected.intersection(visible)
                                hidden = remaining.isEmpty
                                samples.append(["readable": true, "remainingOwners": remaining.sorted(), "elapsedMs": elapsed()])
                                if hidden == true { break }
                            } else { hidden = nil; samples.append(["readable": false, "elapsedMs": elapsed()]) }
                            Thread.sleep(forTimeInterval: 0.05)
                        } while Date() < deadline
                        attempt["visualConfirmationMs"] = elapsed() - verifyStart
                        guard hidden == true else { throw hidden == nil ? MenuBarVisibilityError.unreadableLayout : MenuBarVisibilityError.layout }
                    }
                    attempt["totalMs"] = elapsed()

                } else {
                    try restoreAll()
                    cacheLock.lock(); cachedIcons = []; cacheLock.unlock()
                }
            } catch {
                var failureError = error
                if folded { do { try restoreAll() } catch { failureError = MenuBarVisibilityError.rollback } }
                Self.log.error("Native menu operation failed: folded=\(folded, privacy: .public) reason=\(failureError.localizedDescription, privacy: .public)")
                let pending = (try? storage.journal().isEmpty) != true || (try? system.journal().isEmpty) != true
                if !pending { cacheLock.lock(); cachedIcons = []; cacheLock.unlock() }
                failure = MenuBarLayoutFailure(failureError.localizedDescription, stillFolded: pending)
            }
            if folded {
                attempt["samples"] = samples
                attempt["succeeded"] = failure == nil
                if let failure { attempt["failure"] = failure.message; attempt["recoveryPending"] = failure.stillFolded }
                storage.saveAttempt(attempt)
            }
            DispatchQueue.main.async { completion(failure) }
        }
    }

    static func inspectConfiguration(itemOwners: Set<String> = []) -> [String: Any] {
        let storage = NativeMenuBarVisibilityStorage()
        let pending = (try? storage.journal().count) ?? -1
        do {
            let records = try MenuBarVisibilityRecords(data: storage.read())
            var result: [String: Any] = ["configurationReady": true, "trackedApplicationCount": records.states.count,
                    "records": records.diagnosticRows,
                    "pendingRestoreCount": pending, "nativeFoldInteractionVerified": false]
            result["pendingSystemRestoreCount"] = (try? SystemMenuVisibility().journal().count) ?? -1
            result["transport"] = "explicit-controlcenter-container"
            if let attempt = storage.lastAttempt() { result["lastFoldAttempt"] = attempt }
            do {
                result["controllingOwners"] = try records.controllingOwners(for: itemOwners).sorted()
                result["ownerMappingReady"] = true
            } catch {
                result["ownerMappingReady"] = false
                result["ownerMappingFailure"] = error.localizedDescription
            }
            return result
        } catch {
            return ["configurationReady": false, "reason": error.localizedDescription,
                    "pendingRestoreCount": pending, "nativeFoldInteractionVerified": false]
        }
    }
}
