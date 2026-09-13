import SwiftData

/// In-memory store for `#Preview`s. Returns nil rather than crashing the
/// canvas when the container can't be built.
enum PreviewStore {
    @MainActor
    static func make() -> WorkoutStore? {
        guard let container = try? ModelContainer.dagym(inMemory: true) else { return nil }
        return WorkoutStore(context: ModelContext(container))
    }
}
