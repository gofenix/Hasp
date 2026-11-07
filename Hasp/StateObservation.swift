import Observation

/// Bridges main-actor model changes to AppKit. Observation fires before a
/// mutation; re-arm and deliver on the next actor turn to read settled values
/// and coalesce a burst. A stopped observer cannot deliver a queued callback.
@MainActor final class StateObservation {
    private let read: () -> Void
    private let didChange: () -> Void
    private var generation = 0
    private var active = true

    init(read: @escaping () -> Void, didChange: @escaping () -> Void) {
        self.read = read
        self.didChange = didChange
        arm()
    }

    func stop() { active = false; generation += 1 }

    private func arm() {
        let revision = generation
        withObservationTracking(read) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == revision else { return }
                self.arm()
                self.didChange()
            }
        }
    }
}
