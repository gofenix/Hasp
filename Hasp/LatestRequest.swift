import Foundation

/// One operation per resource. An in-flight operation finishes normally; only
/// the newest pending intent is subsequently executed. Late results cannot
/// overwrite the presentation of a newer intent.
@MainActor
final class LatestRequest<Value: Equatable & Sendable> {
    private var revision = 0
    private var desired: (revision: Int, value: Value)?
    private var running = false
    private let operation: @MainActor (Value) async -> Bool
    private let completion: @MainActor (Value, Bool) -> Void

    init(operation: @escaping @MainActor (Value) async -> Bool, completion: @escaping @MainActor (Value, Bool) -> Void) {
        self.operation = operation
        self.completion = completion
    }

    func submit(_ value: Value) {
        revision += 1
        desired = (revision, value)
        guard !running else { return }
        running = true
        Task { [self] in
            while let request = desired {
                let ok = await operation(request.value)
                if request.revision == revision || (ok && desired?.value == request.value) {
                    let value = desired?.value ?? request.value
                    desired = nil
                    completion(value, ok)
                }
            }
            running = false
        }
    }
}

/// Preserve existing row positions while the panel is being used. Newly
/// discovered rows append; disappeared rows are removed. Reopening can sort.
enum StableRows {
    static func ordered<Item: Identifiable>(_ next: [Item], previous: [Item], preserve: Bool) -> [Item] where Item.ID: Hashable {
        guard preserve else { return next }
        let index = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        let oldIDs = Set(previous.map(\.id))
        return previous.compactMap { index[$0.id] } + next.filter { !oldIDs.contains($0.id) }
    }
}
