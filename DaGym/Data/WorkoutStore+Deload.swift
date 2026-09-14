import Foundation
import GymCore
import SwiftData

/// A suggested deload, for the Home "why a deload?" card.
struct DeloadSuggestionInfo: Hashable {
    var reason: String
    /// The Coach card's own fingerprint for this evidence (`CoachCard.fingerprint` for
    /// `.deloadOverdue`) — the key a dismissal is stored under, shared with the Coach tab so
    /// dismissing here silences there and vice versa.
    var fingerprint: String
}

extension WorkoutStore {
    /// A suggested deload from stalls, e1RM regression, rising RPE at the same load, or
    /// accumulated hard weeks (plan.md §6.5) — nil when nothing warrants one, the user snoozed it
    /// (`snoozedUntil` is `Preferences.deloadSnoozedUntil`), or the same evidence was already
    /// dismissed or approved on the Coach tab within `CoachRule.deloadOverdue`'s cooldown.
    ///
    /// This is literally the Coach tab's `.deloadOverdue` card, read through `CoachEngine`: same
    /// lift snapshots, same wording, same fingerprint, same dismissal rows. It used to be a
    /// parallel implementation over four hard-coded "main lifts" named "Bench"/"Squat"/… with its
    /// own dismissal stored in `Preferences` — so the two screens showed different text for the
    /// same problem and dismissing either one did nothing to the other.
    func deloadSuggestion(
        snoozedUntil: Date?, weeklyGoal: Int = 4, now: Date = Date(), calendar: Calendar = .current
    ) -> DeloadSuggestionInfo? {
        if let snoozedUntil, snoozedUntil > now { return nil }
        // Fetched once and shared: `coachLiftSnapshots` would otherwise re-query the whole
        // finished-workout list once per lift.
        let finishedWorkouts = finishedWorkoutModelsNewestFirst()
        // Only the three fields the deload rule reads — Home refreshes on every store change, and
        // a full `coachInput()` would also compute recovery, body series, PRs and milestones.
        let input = CoachInput(
            lifts: coachLiftSnapshots(finishedWorkouts: finishedWorkouts),
            hardWeeksInARow: hardWeekStreak(
                weeklyGoal: weeklyGoal, calendar: calendar, now: now, finishedWorkouts: finishedWorkouts
            ),
            interactions: coachInteractions()
        )
        guard let card = CoachEngine.deloadCard(for: input, now: now),
              !CoachEngine.isSuppressed(card, interactions: input.interactions, now: now) else {
            return nil
        }
        return DeloadSuggestionInfo(reason: card.body, fingerprint: card.fingerprint)
    }

    /// Records a Home-side "Not now" as the same `.deloadOverdue` dismissal the Coach tab writes,
    /// so the card stays down on both screens for its cooldown.
    func dismissDeloadSuggestion(_ suggestion: DeloadSuggestionInfo, date: Date = Date()) {
        recordCoachInteraction(
            rule: .deloadOverdue, fingerprint: suggestion.fingerprint, outcome: .dismissed, date: date
        )
    }

    /// "Plan a deload week": creates and immediately starts a two-week program — week 1 deload,
    /// week 2 normal — that flags every current routine's next session as a planned deload
    /// (plan.md §6.5's primary action). Unlike a `weeks: 1` program (whose week index is always
    /// `(days / 7 % 1) + 1 == 1`, so it never leaves the deload week), this expires after one
    /// week and, once it does, `activeProgramModel()` hands control back to whichever program was
    /// active before — see `resumeProgramIfDeloadExpired()`.
    func planDeloadWeek() {
        let previous = activeProgramModel()
        for other in fetch(FetchDescriptor<ProgramModel>()) { other.isActive = false }
        if let previous, previous.name != Self.deloadProgramName {
            UserDefaults.standard.set(previous.id.uuidString, forKey: Self.deloadPreviousProgramIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.deloadPreviousProgramIDKey)
        }
        let model = ProgramModel(name: Self.deloadProgramName, weeks: 2, startedAt: Date(), isActive: true)
        model.routineIDs = routines().map(\.id)
        context.insert(model)
        let deloadWeek = ProgramWeekModel(index: 1, kind: ProgramWeekKind.deload.rawValue, program: model)
        let normalWeek = ProgramWeekModel(index: 2, kind: ProgramWeekKind.normal.rawValue, program: model)
        context.insert(deloadWeek)
        context.insert(normalWeek)
        model.programWeeks = [deloadWeek, normalWeek]
        save()
    }

    // MARK: - Helpers

    /// Shared with `WorkoutStore+Programs.swift`'s `resumeProgramIfDeloadExpired()`.
    static let deloadProgramName = "Deload Week"
    static let deloadPreviousProgramIDKey = "deloadPreviousProgramID"

    /// Consecutive recent weeks (working back from this week, or from the last complete one when
    /// this week hasn't met the goal yet) that met `weeklyGoal` with no
    /// planned deload session in them — a simple proxy for "accumulated weeks of hard training
    /// without a lighter week" (A4b: a deload week breaks the streak even if it also hit the
    /// workout count, and the count is the user's actual `Preferences.weeklyGoal`, not a
    /// hard-coded 3).
    /// Exposed (not `private`) so `WorkoutStore+Coach.swift`'s adapter can reuse the same
    /// hard-week count for `CoachInput.hardWeeksInARow` rather than re-deriving it.
    /// `now` is passed in, never read: this feeds `CoachInput.hardWeeksInARow`, and an adapter
    /// that reads the clock behind the engine's back makes a pinned-`now` test a lie.
    func hardWeekStreak(
        weeklyGoal: Int, calendar: Calendar = .current, now: Date = Date(),
        finishedWorkouts: [WorkoutModel]? = nil
    ) -> Int {
        var weekCounts: [Date: Int] = [:]
        var weeksWithDeload: Set<Date> = []
        for workout in finishedWorkouts ?? finishedWorkoutModelsNewestFirst() {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start else {
                continue
            }
            weekCounts[start, default: 0] += 1
            if (workout.exercises ?? []).contains(where: \.wasPlannedDeload) {
                weeksWithDeload.insert(start)
            }
        }
        var streak = 0
        var cursor = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        // The week in progress has not had a chance to meet the goal yet. Starting the walk on it
        // unconditionally meant eight hard weeks read as 0 every Monday and Tuesday, so the
        // deload rule's `hardWeeksInARow` arm could only ever fire on the last day or two of a
        // week — count it when it has already met the goal, otherwise start from the last
        // complete week. A deload logged this week still breaks the streak (the loop's own
        // condition), which is the whole point of the check.
        let goal = max(1, weeklyGoal)
        if (weekCounts[cursor] ?? 0) < goal, !weeksWithDeload.contains(cursor),
           let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) {
            cursor = previous
        }
        while (weekCounts[cursor] ?? 0) >= goal, !weeksWithDeload.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
