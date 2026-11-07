import AppKit
import Foundation

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

@main enum ObservationTests {
    @MainActor static func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            precondition(Date() < deadline, "Observation callback timed out")
            try! await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor static func main() async {
        let state = AppearanceState()
        var updates: [Bool] = []
        let observation = StateObservation(read: { _ = state.isDark }, didChange: { updates.append(state.isDark) })
        state.isDark = true
        state.isDark = false
        state.isDark = true
        precondition(updates.isEmpty, "AppKit must read after the mutation, not during willSet")
        await wait { updates == [true] }
        state.isDark = false
        await wait { updates == [true, false] }
        state.isDark = true
        observation.stop()
        try! await Task.sleep(for: .milliseconds(10))
        precondition(updates == [true, false], "Stopped observers cannot deliver queued changes")

        let suite = "app.hasp.observation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: SettingsStore(defaults: defaults))
        var appearanceChanges = 0
        var audioChanges = 0
        var preparationChanges = 0
        let appearance = StateObservation(read: { _ = model.isDark }, didChange: { appearanceChanges += 1 })
        let audio = StateObservation(read: { _ = model.outputs }, didChange: { audioChanges += 1 })
        let preparation = StateObservation(read: { model.trackPanelPresentation() }, didChange: { preparationChanges += 1 })
        let output = OutputItem(id: "fake", name: "Fake", kind: .mac, isCurrent: true, pending: false)
        model.outputs = [output]
        await wait { audioChanges == 1 && preparationChanges == 1 }
        precondition(appearanceChanges == 0, "Audio updates must not invalidate appearance")
        model.outputs = [output]
        try! await Task.sleep(for: .milliseconds(10))
        precondition(audioChanges == 1 && preparationChanges == 1, "Identical snapshots must be silent")
        model.isDark = true
        await wait { appearanceChanges == 1 && preparationChanges == 2 }
        precondition(audioChanges == 1, "Appearance updates must not invalidate audio")
        appearance.stop(); audio.stop(); preparation.stop()
        print("Observation passed: settled reads; burst coalescing; re-arm; stale callback cancellation; domain isolation; unchanged snapshots")
    }
}
