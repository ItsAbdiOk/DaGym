import Foundation
import GymCore

/// Superset-aware pieces of `WorkoutSession` (plan §6.1): a group rests once per round using
/// the longest rest in the group, reorders as one unit, and a swap after logged sets keeps
/// those sets by appending the substitute instead of replacing the entry.
extension WorkoutSession {
    /// Consecutive runs of exercises sharing a non-nil `supersetGroup`; singletons are one-element
    /// chunks. The Active Workout list and the reorder sheet both render these.
    var groupedIndices: [[Int]] {
        var result: [[Int]] = []
        var start = 0
        while start < exercises.count {
            let group = exercises[start].supersetGroup
            var chunk = [start]
            var next = start + 1
            if group != nil {
                while next < exercises.count, exercises[next].supersetGroup == group {
                    chunk.append(next)
                    next += 1
                }
            }
            result.append(chunk)
            start = next
        }
        return result
    }

    var hasUndoneSets: Bool { exercises.contains { $0.sets.contains { !$0.isDone } } }

    /// Seconds to rest after finishing `set` of `exercises[exerciseIndex]`: nothing while a
    /// superset partner still owes a set this round, the group's longest rest once the round is
    /// over, the exercise's own rest for a singleton, and nothing at all after the session's
    /// last set.
    func restSeconds(after exerciseIndex: Int, set setIndex: Int) -> Int {
        guard hasUndoneSets else { return 0 }
        let members = supersetMembers(containing: exerciseIndex)
        guard members.count > 1 else { return exercises[exerciseIndex].exercise.restSeconds }
        if roundPartner(members: members, round: setIndex, excluding: exerciseIndex) != nil { return 0 }
        return members.map { exercises[$0].exercise.restSeconds }.max() ?? 0
    }

    func supersetMembers(containing exerciseIndex: Int) -> [Int] {
        groupedIndices.first { $0.contains(exerciseIndex) } ?? [exerciseIndex]
    }

    /// Another group member with an undone set in this round — the ones after `exerciseIndex`
    /// first, so the label follows the group's order.
    func roundPartner(members: [Int], round: Int, excluding exerciseIndex: Int) -> Int? {
        let others = members.filter { $0 > exerciseIndex } + members.filter { $0 < exerciseIndex }
        return others.first { index in
            let sets = exercises[index].sets
            return sets.indices.contains(round) && !sets[round].isDone
        }
    }

    func nextRoundSet(members: [Int], round: Int) -> SetEntry? {
        for index in members where exercises[index].sets.indices.contains(round) {
            return exercises[index].sets[round]
        }
        return nil
    }

    // MARK: Reorder

    /// Moves whole units — a superset group travels together — using the offsets the reorder
    /// sheet's `onMove` hands over for its `groupedIndices` rows.
    func moveUnits(fromOffsets source: IndexSet, toOffset destination: Int) {
        let units = groupedIndices.map { $0.map { exercises[$0] } }
        let moving = source.map { units[$0] }
        var remaining = units.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertAt)
        exercises = remaining.flatMap { $0 }
    }

    // MARK: Swap

    func hasLoggedSets(entryID: UUID) -> Bool { doneCount(entryID: entryID) > 0 }

    func doneCount(entryID: UUID) -> Int {
        exercises.first { $0.id == entryID }?.doneCount ?? 0
    }

    func isInSuperset(entryID: UUID) -> Bool {
        guard let index = exercises.firstIndex(where: { $0.id == entryID }) else { return false }
        return supersetMembers(containing: index).count > 1
    }

    /// Swap on an entry with nothing logged yet: the same rows, a different exercise.
    func replaceInPlace(entryID: UUID, with candidate: ExerciseInfo) {
        guard let index = exercises.firstIndex(where: { $0.id == entryID }) else { return }
        exercises[index].exercise = candidate
        exercises[index].wasSubstitution = true
    }

    /// Swap on an entry that already has logged sets: the entry stays (so history and PRs keep
    /// crediting it) and `substitute` goes in after it — directly after it, inside the superset,
    /// when `keepInSuperset`; otherwise after the group's last member, ungrouped.
    func insertSubstitute(_ substitute: WorkoutExerciseEntry, after entryID: UUID, keepInSuperset: Bool) {
        guard let index = exercises.firstIndex(where: { $0.id == entryID }) else { return }
        var entry = substitute
        entry.wasSubstitution = true
        let group = exercises[index].supersetGroup
        if keepInSuperset, group != nil {
            entry.supersetGroup = group
            exercises.insert(entry, at: index + 1)
        } else {
            entry.supersetGroup = nil
            let last = supersetMembers(containing: index).last ?? index
            exercises.insert(entry, at: last + 1)
        }
    }

    // MARK: Add set

    /// Appends a set copied from the exercise's last row. A drop set seeds 80 % of that weight,
    /// snapped down to the exercise's increment so it's loadable.
    func addSet(exerciseID: UUID, kind: SetKind) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let entry = exercises[index]
        let template = entry.sets.last
        var weightKg = template?.weightKg ?? 0
        if kind == .drop, let template {
            weightKg = Self.dropWeightKg(from: template.weightKg, increment: entry.exercise.incrementKg)
        }
        exercises[index].sets.append(SetEntry(kind: kind, weightKg: weightKg, reps: template?.reps ?? 0))
    }

    static func dropWeightKg(from weightKg: Double, increment: Double) -> Double {
        let target = weightKg * 0.8
        guard increment > 0 else { return target }
        return (target / increment + 1e-9).rounded(.down) * increment
    }
}
