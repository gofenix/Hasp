import AppKit
import Observation
import CoreAudio
import Foundation

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

actor OperationGate<Value: Sendable> {
    var history: [Value] = []
    private var pending: [CheckedContinuation<Bool, Never>] = []
    func run(_ value: Value) async -> Bool {
        history.append(value)
        return await withCheckedContinuation { pending.append($0) }
    }
    func release(_ ok: Bool) { pending.removeFirst().resume(returning: ok) }
}

actor SnapshotGate {
    var count = 0
    private var pending: [CheckedContinuation<HardwareSnapshot, Never>] = []
    func read() async -> HardwareSnapshot {
        count += 1
        return await withCheckedContinuation { pending.append($0) }
    }
    func release(_ snapshot: HardwareSnapshot) { pending.removeFirst().resume(returning: snapshot) }
}

actor FakeHardware {
    var snapshot = HardwareSnapshot(outputs: [
        ListedOutput(uid: "mac", name: "Mac", transport: kAudioDeviceTransportTypeBuiltIn, isCurrent: true),
        ListedOutput(uid: "wired", name: "Wired", transport: kAudioDeviceTransportTypeBuiltIn, isCurrent: false)
    ], devices: [PairedDevice(address: "test", name: "Keyboard", kind: .keyboard, connected: true)], batteries: [:])
    func selected(_ uid: String) { for i in snapshot.outputs.indices { snapshot.outputs[i].isCurrent = snapshot.outputs[i].uid == uid } }
    func connected(_ value: Bool) { snapshot.devices[0].connected = value }
}

@main enum SwitchOptimizationTests {
    @MainActor static func wait(_ predicate: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !(await predicate()) {
            precondition(Date() < deadline, "Timed out waiting for test operation")
            try! await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "app.hasp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = OperationGate<Bool>()
        let audio = OperationGate<String>()
        let devices = OperationGate<Bool>()
        let hardware = FakeHardware()
        let services = SwitchServices(
            appearance: { await appearance.run($0.dark) },
            audio: { uid in
                let ok = await audio.run(uid)
                if ok { await hardware.selected(uid) }
                return ok
            },
            device: { _, value in
                let ok = await devices.run(value)
                if ok { await hardware.connected(value) }
                return ok
            },
            snapshot: { _ in await hardware.snapshot }
        )
        let model = AppModel(services: services, store: SettingsStore(defaults: defaults))
        model.outputs = [
            OutputItem(id: "mac", name: "Mac", kind: .mac, isCurrent: true, pending: false),
            OutputItem(id: "wired", name: "Wired", kind: .wired, isCurrent: false, pending: false)
        ]
        model.inputs = [DeviceItem(address: "test", name: "Keyboard", kind: .keyboard, connected: true, pending: false, failed: false)]
        model.preparePanelPresentation()

        var audioSignals = 0
        var appearanceSignals = 0
        var globalSignals = 0
        let observers = [
            StateObservation(read: { _ = (model.outputs, model.audioState.recentHeadphoneID) }, didChange: { audioSignals += 1 }),
            StateObservation(read: { _ = (model.isDark, model.scheduleMode, model.appearanceState.requested, model.permissionMessage) }, didChange: { appearanceSignals += 1 }),
            StateObservation(read: { _ = (model.audioState, model.appearanceState, model.deviceState, model.menuState) }, didChange: { globalSignals += 1 })
        ]
        let identical = model.outputs
        for _ in 0..<40 { model.outputs = identical }
        precondition(audioSignals == 0 && globalSignals == 0, "Identical snapshots must not invalidate the panel")

        model.setAppearanceSwitch(true)
        precondition(model.appearanceSwitchOn && !model.isDark, "Intent is immediate; material waits for confirmation")
        await wait { await appearance.history.count == 1 }
        // The backend remains blocked while the main actor handles 80 new intents.
        var handlerTimes: [Double] = []
        for i in 0..<80 {
            let start = DispatchTime.now().uptimeNanoseconds
            model.setAppearanceSwitch(i.isMultiple(of: 2))
            handlerTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        precondition(!model.appearanceSwitchOn && !model.isDark)
        var heartbeatGaps: [Double] = []
        for _ in 0..<100 {
            let start = DispatchTime.now().uptimeNanoseconds
            try! await Task.sleep(for: .milliseconds(20))
            heartbeatGaps.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        await appearance.release(true)
        await wait { await appearance.history.count == 2 }
        precondition(!model.isDark && !model.appearanceSwitchOn, "Old success cannot overwrite latest off intent")
        let appearanceHistory = await appearance.history
        precondition(appearanceHistory == [true, false])
        await appearance.release(true)
        await wait { model.appearanceState.requested == nil }
        precondition(!model.isDark && audioSignals == 0)

        await wait { appearanceSignals > 0 }
        let appearanceBeforeAudio = appearanceSignals
        let initialOrder = model.outputs.map(\.id)
        model.selectOutput(model.outputs[1], on: true)
        precondition(model.outputs[1].switchOn && !model.outputs[0].switchOn)
        await wait { await audio.history.count == 1 }
        model.selectOutput(model.outputs[0], on: true)
        precondition(model.outputs[0].switchOn && !model.outputs[1].switchOn)
        await audio.release(true)
        await wait { await audio.history.count == 2 }
        precondition(model.outputs[0].switchOn, "Stale audio reply must not replace latest intent")
        await audio.release(true)
        await wait { !model.outputs.contains(where: \.pending) }
        await model.finishHardwareRefresh()
        precondition(model.outputs.map(\.id) == initialOrder)
        precondition(model.outputs[0].isCurrent && appearanceSignals == appearanceBeforeAudio && globalSignals == 0)

        // A successful selection keeps the clicked row stationary.
        model.selectOutput(model.outputs[1], on: true)
        await wait { await audio.history.count == 3 }
        await audio.release(true)
        await wait { !model.outputs.contains(where: \.pending) }
        await model.finishHardwareRefresh()
        precondition(model.outputs.map(\.id) == initialOrder && model.outputs[1].isCurrent)
        model.panelDidClose()
        model.preparePanelPresentation()
        precondition(model.outputs.first?.id == "wired", "Reopen may sort by current output")

        model.toggleDevice(model.inputs[0], on: false)
        precondition(!model.inputs[0].switchOn && model.inputs[0].subtitle == "正在断开")
        await wait { await devices.history.count == 1 }
        await devices.release(false)
        await wait { !model.inputs[0].pending }
        await model.finishHardwareRefresh()
        precondition(model.inputs[0].switchOn && model.inputs[0].subtitle == "未能断开，请重试")

        model.setAppearanceSwitch(true)
        await wait { await appearance.history.count == 3 }
        await appearance.release(false)
        await wait { model.appearanceState.requested == nil }
        precondition(!model.isDark && !model.appearanceSwitchOn && model.permissionMessage != nil)

        // Returning to the in-flight target coalesces the intermediate opposite
        // intent without executing a redundant second successful operation.
        model.setAppearanceSwitch(true)
        await wait { await appearance.history.count == 4 }
        model.setAppearanceSwitch(false)
        model.setAppearanceSwitch(true)
        await appearance.release(true)
        await wait { model.appearanceState.requested == nil }
        let coalescedHistory = await appearance.history
        precondition(coalescedHistory.count == 4 && model.isDark)

        model.selectOutput(model.outputs.first(where: { $0.id == "mac" })!, on: true)
        await wait { await audio.history.count == 4 }
        await audio.release(false)
        await wait { !model.outputs.contains(where: \.pending) }
        await model.finishHardwareRefresh()
        precondition(model.outputs.first(where: { $0.id == "mac" })!.failed)
        precondition(model.outputs.first(where: { $0.id == "wired" })!.switchOn)

        model.toggleDevice(model.inputs[0], on: false)
        await wait { await devices.history.count == 2 }
        model.toggleDevice(model.inputs[0], on: true)
        await devices.release(true)
        await wait { await devices.history.count == 3 }
        precondition(model.inputs[0].switchOn && model.inputs[0].pending)
        await devices.release(true)
        await wait { !model.inputs[0].pending }
        await model.finishHardwareRefresh()
        precondition(model.inputs[0].connected && !model.inputs[0].failed)

        // An old hardware read arriving after a command must be discarded.
        let snapshotGate = SnapshotGate()
        let staleAudio = OperationGate<String>()
        let stale = AppModel(services: SwitchServices(
            appearance: { _ in false }, audio: { await staleAudio.run($0) },
            device: { _, _ in false }, snapshot: { _ in await snapshotGate.read() }
        ), store: SettingsStore(defaults: defaults))
        stale.outputs = identical
        stale.preparePanelPresentation()
        stale.requestHardwareRefresh(includeBattery: false)
        await wait { await snapshotGate.count == 1 }
        stale.selectOutput(stale.outputs[1], on: true)
        await wait { await staleAudio.history.count == 1 }
        await staleAudio.release(true)
        await wait { !stale.outputs[1].pending }
        var oldSnapshot = await hardware.snapshot
        for i in oldSnapshot.outputs.indices { oldSnapshot.outputs[i].isCurrent = oldSnapshot.outputs[i].uid == "mac" }
        await snapshotGate.release(oldSnapshot)
        await wait { await snapshotGate.count == 2 }
        precondition(stale.outputs[1].isCurrent, "Pre-command snapshot cannot roll the result back")
        await snapshotGate.release(await hardware.snapshot)
        await stale.finishHardwareRefresh()
        precondition(stale.outputs[1].isCurrent)

        observers.forEach { $0.stop() }
        withExtendedLifetime(observers) {}
        let ordered = handlerTimes.sorted()
        let report: [String: Any] = [
            "scope": "Actual AppModel handlers with blocked fake backend; not on-screen frame timings",
            "handlerSamples": handlerTimes.count,
            "handlerP95Ms": ordered[Int(Double(ordered.count - 1) * 0.95)],
            "handlerMaxMs": ordered.last!,
            "blockedBackendHeartbeatMaxGapMs": heartbeatGaps.max()!,
            "unchangedSnapshotSignals": 0,
            "globalPanelSignals": globalSignals,
            "passed": ["latest intent", "stale reply", "failure rollback", "domain isolation", "stable rows", "stale hardware snapshot"]
        ]
        precondition(ordered.last! < 50, "Click handler unexpectedly blocked")
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let reportURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("switch-handler-regression.json")
        try data.write(to: reportURL)
        print(String(data: data, encoding: .utf8)!)
    }
}
