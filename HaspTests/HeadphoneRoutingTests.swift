import AppKit
import CoreAudio
import Foundation

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

private let firstAddress = "AA-BB-CC-DD-EE-01"
private let secondAddress = "AA-BB-CC-DD-EE-02"

private actor HeadphoneHardware {
    var snapshot = HardwareSnapshot(outputs: [
        ListedOutput(uid: "mac", name: "Mac", transport: kAudioDeviceTransportTypeBuiltIn, isCurrent: true)
    ], devices: [
        PairedDevice(address: firstAddress, name: "OpenDots", kind: .headphone, connected: false),
        PairedDevice(address: secondAddress, name: "OpenDots", kind: .headphone, connected: false),
        PairedDevice(address: "AA-BB-CC-DD-EE-03", name: "Unclassified", kind: .other, connected: false)
    ], batteries: [:])
    var connections: [(String, Bool)] = []
    var selections: [String] = []
    var failSelection = false
    private var pending: [(String, Bool, CheckedContinuation<Bool, Never>)] = []

    func connect(_ address: String, _ connected: Bool) async -> Bool {
        connections.append((address, connected))
        return await withCheckedContinuation { pending.append((address, connected, $0)) }
    }

    func release(_ ok: Bool, address target: String? = nil) {
        let index = target.map { address in pending.firstIndex { $0.0 == address }! } ?? 0
        let (address, connected, continuation) = pending.remove(at: index)
        if ok {
            let index = snapshot.devices.firstIndex { $0.address == address }!
            snapshot.devices[index].connected = connected
            if !connected {
                snapshot.outputs.removeAll { AudioOutputInventory.bluetoothAddress($0) == AudioOutputInventory.addressKey(address) }
                if !snapshot.outputs.contains(where: \.isCurrent) { snapshot.outputs[0].isCurrent = true }
            }
        }
        continuation.resume(returning: ok)
    }

    func addEndpoint(_ address: String) {
        snapshot.outputs.append(ListedOutput(uid: address + ":output", name: "OpenDots",
            transport: kAudioDeviceTransportTypeBluetooth, isCurrent: false))
    }

    func select(_ uid: String) -> Bool {
        selections.append(uid)
        if failSelection { failSelection = false; return false }
        for index in snapshot.outputs.indices { snapshot.outputs[index].isCurrent = snapshot.outputs[index].uid == uid }
        return true
    }

    func failNextSelection() { failSelection = true }

    func markConnected(_ address: String) {
        snapshot.devices[snapshot.devices.firstIndex { $0.address == address }!].connected = true
        if !snapshot.outputs.contains(where: { AudioOutputInventory.bluetoothAddress($0) == AudioOutputInventory.addressKey(address) }) {
            addEndpoint(address)
        }
    }
}

@main enum HeadphoneRoutingTests {
    @MainActor static func wait(_ predicate: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !(await predicate()) {
            precondition(Date() < deadline, "Timed out waiting for headphone operation")
            try! await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "HaspHeadphoneRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = HeadphoneHardware()
        let model = AppModel(services: SwitchServices(
            appearance: { _ in false }, audio: { await hardware.select($0) },
            device: { await hardware.connect($0, $1) }, snapshot: { _ in await hardware.snapshot },
            availableOutputs: { await hardware.snapshot.outputs }, audioReadyTimeout: 0.35
        ), store: SettingsStore(defaults: defaults))
        model.requestHardwareRefresh(includeBattery: false)
        await model.finishHardwareRefresh()
        model.preparePanelPresentation()
        let idA = "bluetooth:" + AudioOutputInventory.addressKey(firstAddress)
        let idB = "bluetooth:" + AudioOutputInventory.addressKey(secondAddress)
        func row(_ id: String) -> OutputItem { model.outputs.first { $0.id == id }! }
        let initialOrder = model.outputs.map(\.id)
        precondition(row(idA).subtitle == "未连接" && row(idA).actionTitle == "连接并使用")
        precondition(model.inputs.contains { $0.name == "Unclassified" }, "Don't discard unknown paired devices")
        precondition(model.outputs.count == 3, "Both disconnected headphones must remain visible")

        // A native connection can block while the user immediately selects Mac.
        model.selectOutput(row(idA), on: true)
        await wait { await hardware.connections.count == 1 }
        precondition(row(idA).pending && row(idA).subtitle == "连接中…")
        model.selectOutput(row("mac"), on: true)
        await wait { await hardware.selections.count == 1 }
        await wait { !row("mac").pending }
        precondition(row("mac").isCurrent && !row(idA).pending)
        await hardware.release(true)
        try await Task.sleep(for: .milliseconds(30))
        let earlySelections = await hardware.selections
        precondition(earlySelections == ["mac"], "Late connection must not steal audio")
        model.requestHardwareRefresh(includeBattery: false)
        await model.finishHardwareRefresh()

        // Link success is not enough: wait for the address-matched audio endpoint.
        model.selectOutput(row(idA), on: true)
        await wait { row(idA).operation == .waitingForOutput }
        precondition(!row(idA).isCurrent)
        await hardware.addEndpoint(firstAddress)
        await wait { !row(idA).pending }
        await model.finishHardwareRefresh()
        precondition(row(idA).isCurrent && row(idA).connected)
        precondition(model.outputs.map(\.id) == initialOrder, "Connection must neither add a duplicate nor move the row")
        precondition(model.outputs.filter { $0.bluetoothAddress == firstAddress }.count == 1)
        precondition(!row(idB).isCurrent, "Same-name headphones must not be confused")

        model.selectOutput(row(idB), on: true)
        await wait { await hardware.connections.count == 2 }
        await hardware.release(false)
        await wait { !row(idB).pending }
        await model.finishHardwareRefresh()
        precondition(row(idB).failure == .connection && row(idA).isCurrent)
        // Retry connects successfully, but its output doesn't appear in time.
        model.selectOutput(row(idB), on: true)
        await wait { await hardware.connections.count == 3 }
        await hardware.release(true)
        await wait { !row(idB).pending }
        await model.finishHardwareRefresh()
        precondition(row(idB).connected && row(idB).failure == .routing)
        precondition(row(idB).subtitle == "已连接，声音切换失败，请重试")
        precondition(row(idA).isCurrent, "A missing endpoint must preserve the current route")

        await hardware.addEndpoint(secondAddress)
        await hardware.failNextSelection()
        model.selectOutput(row(idB), on: true)
        await wait { !row(idB).pending }
        await model.finishHardwareRefresh()
        precondition(row(idB).failure == .routing && row(idA).isCurrent)
        model.selectOutput(row(idB), on: true)
        await wait { !row(idB).pending }
        await model.finishHardwareRefresh()
        precondition(row(idB).isCurrent && row(idB).failure == nil)

        model.disconnectOutput(row(idB))
        await wait { await hardware.connections.count == 4 }
        precondition(row(idB).operation == .disconnecting)
        await hardware.release(false)
        await wait { !row(idB).pending }
        await model.finishHardwareRefresh()
        precondition(row(idB).connected && row(idB).failure == .disconnection)
        model.disconnectOutput(row(idB))
        await wait { await hardware.connections.count == 5 }
        await hardware.release(true)
        await wait { !row(idB).pending }
        await model.finishHardwareRefresh()
        precondition(!row(idB).connected && row(idB).failure == nil && !row(idB).isCurrent)
        precondition(model.outputs.map(\.id) == initialOrder, "Disconnected paired rows stay available for reconnection")

        let fakeBluetooth = ListedOutput(uid: "AA:BB:CC:DD:EE:01:output", name: "Renamed",
            transport: kAudioDeviceTransportTypeBluetoothLE, isCurrent: true)
        precondition(AudioOutputInventory.endpoint(for: firstAddress, in: [fakeBluetooth]) != nil)
        let nonBluetooth = ListedOutput(uid: firstAddress + ":output", name: "OpenDots",
            transport: kAudioDeviceTransportTypeUSB, isCurrent: false)
        precondition(AudioOutputInventory.endpoint(for: firstAddress, in: [nonBluetooth]) == nil)
        let wrongAddress = ListedOutput(uid: secondAddress + ":output", name: "OpenDots",
            transport: kAudioDeviceTransportTypeBluetooth, isCurrent: false)
        precondition(AudioOutputInventory.endpoint(for: firstAddress, in: [wrongAddress]) == nil)

        // Return to a headphone while its first native connection is still in
        // flight. Both routes share that job; no parallel connects to one device.
        let sharedHardware = HeadphoneHardware()
        let shared = AppModel(services: SwitchServices(
            appearance: { _ in false }, audio: { await sharedHardware.select($0) },
            device: { await sharedHardware.connect($0, $1) }, snapshot: { _ in await sharedHardware.snapshot },
            availableOutputs: { await sharedHardware.snapshot.outputs }
        ), store: SettingsStore(defaults: defaults))
        shared.requestHardwareRefresh(includeBattery: false)
        await shared.finishHardwareRefresh()
        func sharedRow(_ id: String) -> OutputItem { shared.outputs.first { $0.id == id }! }
        shared.selectOutput(sharedRow(idA), on: true)
        await wait { await sharedHardware.connections.count == 1 }
        shared.selectOutput(sharedRow("mac"), on: true)
        shared.selectOutput(sharedRow(idA), on: true)
        await sharedHardware.addEndpoint(firstAddress)
        await sharedHardware.release(true)
        await wait { sharedRow(idA).isCurrent && !sharedRow(idA).pending }
        await shared.finishHardwareRefresh()
        let sharedConnections = await sharedHardware.connections.count
        precondition(sharedConnections == 1, "Returning to the same device must reuse its native connection")
        shared.disconnectOutput(sharedRow(idA))
        await wait { await sharedHardware.connections.count == 2 }
        shared.selectOutput(sharedRow("mac"), on: true)
        shared.selectOutput(sharedRow(idA), on: true)
        await sharedHardware.release(true)
        await wait { await sharedHardware.connections.count == 3 }
        await sharedHardware.addEndpoint(firstAddress)
        await sharedHardware.release(true)
        await wait { sharedRow(idA).isCurrent && !sharedRow(idA).pending }
        await shared.finishHardwareRefresh()
        precondition(sharedRow(idA).connected, "A late disconnect must be followed by the latest reconnect intent")

        // Disconnection is independent per headphone, not another global route intent.
        let independentHardware = HeadphoneHardware()
        await independentHardware.markConnected(secondAddress)
        let independent = AppModel(services: SwitchServices(
            appearance: { _ in false }, audio: { await independentHardware.select($0) },
            device: { await independentHardware.connect($0, $1) }, snapshot: { _ in await independentHardware.snapshot },
            availableOutputs: { await independentHardware.snapshot.outputs }
        ), store: SettingsStore(defaults: defaults))
        independent.requestHardwareRefresh(includeBattery: false)
        await independent.finishHardwareRefresh()
        func independentRow(_ id: String) -> OutputItem { independent.outputs.first { $0.id == id }! }
        independent.activateOutput(independentRow(idA))
        await wait { await independentHardware.connections.count == 1 }
        independent.disconnectOutput(independentRow(idB))
        independent.disconnectOutput(independentRow(idB))
        await wait { await independentHardware.connections.count == 2 }
        await independentHardware.release(false, address: secondAddress)
        await wait { independentRow(idB).failure == .disconnection }
        precondition(independentRow(idA).pending, "Disconnect B cannot clear A's connection progress")
        await independentHardware.addEndpoint(firstAddress)
        await independentHardware.release(true, address: firstAddress)
        await wait { independentRow(idA).isCurrent && !independentRow(idA).pending }
        await independent.finishHardwareRefresh()
        precondition(independentRow(idB).failure == .disconnection)
        let selectionsBeforeRetry = await independentHardware.selections.count
        independent.activateOutput(independentRow(idB))
        await wait { await independentHardware.connections.count == 3 }
        let retry = await independentHardware.connections.last!
        precondition(retry.0 == secondAddress && !retry.1, "Retry must repeat disconnection, not select that output")
        await independentHardware.release(true, address: secondAddress)
        await wait { !independentRow(idB).pending }
        await independent.finishHardwareRefresh()
        let selectionsAfterRetry = await independentHardware.selections.count
        precondition(selectionsBeforeRetry == selectionsAfterRetry && independentRow(idA).isCurrent)
        await independentHardware.markConnected(secondAddress)
        independent.requestHardwareRefresh(includeBattery: false)
        await independent.finishHardwareRefresh()
        independent.disconnectOutput(independentRow(idA))
        independent.disconnectOutput(independentRow(idB))
        await wait { await independentHardware.connections.count == 5 }
        await independentHardware.release(false, address: firstAddress)
        await independentHardware.release(true, address: secondAddress)
        await wait { !independentRow(idA).pending && !independentRow(idB).pending }
        await independent.finishHardwareRefresh()
        precondition(independentRow(idA).connected && independentRow(idA).failure == .disconnection,
                     "A's disconnection failure must survive B's success")
        print("Headphone routing passed: persistent paired rows; identity merge; same-name safety; delayed endpoint; connection/routing/disconnect failures and retry; late connection cannot steal audio; stable rows.")
    }
}
