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
    /// over, the exercise's own rest for a singleton, the short `restPauseSeconds` after a
    /// rest-pause set, and nothing at all after the session's last set.
    ///
    /// `defaultRestSeconds` (Settings → "Default rest") governs two things here, and is the only
    /// reason that stepper isn't decoration: at `0` it is "Off" and no rest ever starts, and
    /// otherwise it is the fallback for an exercise whose own `restSeconds` is unset (`<= 0`).
    func restSeconds(after exerciseIndex: Int, set setIndex: Int) -> Int {
        guard hasUndoneSets, defaultRestSeconds > 0 else { return 0 }
        if exercises[exerciseIndex].sets[setIndex].kind == .restPause { return restPauseSeconds }
        let members = supersetMembers(containing: exerciseIndex)
        guard members.count > 1 else { return rest(of: exerciseIndex) }
        if roundPartner(members: members, round: setIndex, excluding: exerciseIndex) != nil { return 0 }
        return members.map { rest(of: $0) }.max() ?? 0
    }

    /// One exercise's rest, falling back to `defaultRestSeconds` when it carries none.
    private func rest(of exerciseIndex: Int) -> Int {
        let own = exercises[exerciseIndex].exercise.restSeconds
        return own > 0 ? own : defaultRestSeconds
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

    // MARK: Pair / unpair

    enum PairDirection { case previous, next }

    /// Joins an exercise to the neighbour on `direction`'s side: into that neighbour's group
    /// when it has one, otherwise a fresh group for the two of them. An exercise already in a
    /// group leaves it first, so pairing never fuses two groups by accident.
    func pairSuperset(entryID: UUID, with direction: PairDirection) {
        guard let index = exercises.firstIndex(where: { $0.id == entryID }) else { return }
        let neighbour = direction == .previous ? index - 1 : index + 1
        guard exercises.indices.contains(neighbour) else { return }
        if exercises[index].supersetGroup != nil { unpairSuperset(entryID: entryID) }
        let group = exercises[neighbour].supersetGroup ?? nextSupersetGroup
        exercises[neighbour].supersetGroup = group
        exercises[index].supersetGroup = group
        normalizeSupersets()
        Haptics.confirm()
    }

    /// Takes an exercise out of its group. A group left with one member dissolves; one split in
    /// the middle becomes two groups.
    func unpairSuperset(entryID: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == entryID }),
              exercises[index].supersetGroup != nil else { return }
        exercises[index].supersetGroup = nil
        normalizeSupersets()
        Haptics.confirm()
    }

    private var nextSupersetGroup: Int {
        (exercises.compactMap(\.supersetGroup).max() ?? 0) + 1
    }

    /// Re-numbers groups so every group is one consecutive run of at least two exercises —
    /// the shape `groupedIndices` and the reorder sheet assume.
    private func normalizeSupersets() {
        var seen: Set<Int> = []
        for chunk in groupedIndices {
            guard let first = chunk.first, let group = exercises[first].supersetGroup else { continue }
            if chunk.count < 2 {
                exercises[first].supersetGroup = nil
            } else if !seen.insert(group).inserted {
                let fresh = nextSupersetGroup
                for index in chunk { exercises[index].supersetGroup = fresh }
                seen.insert(fresh)
            }
        }
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

    /// Inserts a set directly below `setID`, seeded from that row: a drop set at 80 % of its
    /// weight (snapped to the increment), anything else a straight copy.
    func insertSet(exerciseID: UUID, after setID: UUID, kind: SetKind) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        let template = exercises[ei].sets[si]
        var weightKg = template.weightKg
        if kind == .drop {
            weightKg = Self.dropWeightKg(from: weightKg, increment: exercises[ei].exercise.incrementKg)
        }
        exercises[ei].sets.insert(SetEntry(kind: kind, weightKg: weightKg, reps: template.reps), at: si + 1)
        Haptics.step()
    }

    /// Puts a set back where it was — the undo half of `removeSet`.
    func insertSet(_ set: SetEntry, at index: Int, exerciseID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[ei].sets.insert(set, at: min(index, exercises[ei].sets.count))
    }

    /// The ± steppers: nudges weight by `weightDelta` and reps by `repsDelta`, never below zero.
    func adjustSet(exerciseID: UUID, setID: UUID, weightDelta: Double = 0, repsDelta: Int = 0) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].weightKg = max(0, exercises[ei].sets[si].weightKg + weightDelta)
        exercises[ei].sets[si].reps = max(0, exercises[ei].sets[si].reps + repsDelta)
        Haptics.step()
    }

    static func dropWeightKg(from weightKg: Double, increment: Double) -> Double {
        let target = weightKg * 0.8
        guard increment > 0 else { return target }
        return (target / increment + 1e-9).rounded(.down) * increment
    }
}
