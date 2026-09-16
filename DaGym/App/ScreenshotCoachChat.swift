import Foundation
import GymCore

/// The canned coach chat behind the `coachChat` and `coachReview` screenshots: one thread each,
/// written the way `CoachChatEngine` would have written it (tool chips with their subjects, the
/// reply before the card when the model writes text and calls `propose_routine` in one reply,
/// the reviewer's chips prefixed with its short name), so the screen renders the fixture
/// through the same rows the real thing uses. No key, no network: the engine the screen opens
/// on it is idle. `ScreenshotCoachChatTests` validates every draft against the seed library,
/// so a renamed exercise can't leave a broken card in the shot.
///
/// Sized for one 6.9" screen with the transcript anchored at the bottom: the chat shot shows
/// the question, the reply and the card with its rows open; the review shot shows both cards
/// closed with the reviewer's reasoning between them. Everything is trimmed to that — three
/// exercises, one-line reasons, no second opinion on the chat shot.
///
/// The story is a stalled bench. The numbers are the fixture's own — `stalledKg` and the three
/// session lines — not read from the store: the sample history climbs, and a coach quoting it
/// would have nothing to fix.
enum ScreenshotCoachChat {
    static let drafterModelID = CoachChatConfiguration.defaultModelID
    static let reviewerModelID = CoachChatConfiguration.defaultReviewerModelID

    /// The weight the lifter says they are stuck at, and the reset the coach proposes.
    static let stalledKg = 80.0
    static let resetKg = 72.5
    static let question = "Bench has been stuck at \(Int(stalledKg)) kg for three weeks, what do I change?"

    /// Push A sessions are logged 5, 12 and 19 days before the history anchor
    /// (`SampleDataSeeder.dayOffsets`), so the reply's dates line up with the calendar.
    static let sessionDaysAgo = [19, 12, 5]

    private static let dayMonth = Date.FormatStyle().day().month(.abbreviated)

    // MARK: - Threads

    /// The drafter's answer and its reset routine, no second opinion.
    static func chatThread(now: Date) -> CoachChatThread {
        let clock = Clock(start: now.addingTimeInterval(-6 * 60))
        let messages = [CoachChatMessage.user(question, at: clock.next())] + drafterTurn(clock: clock)
        return thread(messages: messages, drafts: [resetRoutine], origins: [.drafter], reviews: [], now: now)
    }

    /// The same answer, but the reviewer put up its own version: two cards, both still proposed.
    /// The reviewer's words are carried by the verdict (drawn above its card) rather than a
    /// transcript row as well, so the shot says them once.
    static func reviewThread(now: Date) -> CoachChatThread {
        let clock = Clock(start: now.addingTimeInterval(-6 * 60))
        var messages: [CoachChatMessage] = [.user(question, at: clock.next())]
        messages += drafterTurn(clock: clock)
        messages += reviewerChips(clock: clock)
        var chip = CoachChatMessage.tool(CoachChatToolName.proposeRoutine.rawValue, at: clock.next())
        chip.text = "Opus · \(chip.text) · \(alternativeRoutine.name)"
        chip.reviewIndex = 0
        messages.append(chip)
        var card = CoachChatMessage.draft(index: 1, summary: alternativeRoutine.summary, at: clock.next())
        card.reviewIndex = 0
        messages.append(card)
        let review = CoachChatReview(
            draftIndex: 0, reviewerModelID: reviewerModelID,
            verdict: .alternative(draftIndex: 1, rationale: alternativeRationale), finishedAt: clock.next()
        )
        return thread(
            messages: messages, drafts: [resetRoutine, alternativeRoutine], origins: [.drafter, .reviewer],
            reviews: [review], now: now
        )
    }

    private static func thread(
        messages: [CoachChatMessage], drafts: [RoutineProposal], origins: [CoachChatDraftOrigin],
        reviews: [CoachChatReview], now: Date
    ) -> CoachChatThread {
        var usage = CoachChatUsage(promptTokens: 12_900, completionTokens: 780)
        usage.byModel[drafterModelID] = CoachChatModelUsage(promptTokens: 12_900, completionTokens: 780)
        if !reviews.isEmpty {
            usage.add(promptTokens: 5_520, completionTokens: 480, model: reviewerModelID)
        }
        return CoachChatThread(
            id: UUID(), createdAt: messages.first?.sentAt ?? now, updatedAt: messages.last?.sentAt ?? now,
            messages: messages, drafts: drafts.map(CoachChatDraft.routine), draftOrigins: origins,
            reviews: reviews, usage: usage
        )
    }

    // MARK: - The drafter's turn

    /// Two lookups, the closing words, then the card — the order the engine appends them in
    /// when the model writes text and calls `propose_routine` in the same reply.
    private static func drafterTurn(clock: Clock) -> [CoachChatMessage] {
        var history = CoachChatMessage.tool(CoachChatToolName.getExerciseHistory.rawValue, at: clock.next())
        history.text += " · Barbell Bench Press - Medium Grip"
        var recent = CoachChatMessage.tool(CoachChatToolName.getRecentWorkouts.rawValue, at: clock.next())
        recent.text += " · 3 weeks"
        var chip = CoachChatMessage.tool(CoachChatToolName.proposeRoutine.rawValue, at: clock.next())
        chip.text += " · \(resetRoutine.name)"
        return [
            history, recent,
            .assistant(reply(now: clock.now), at: clock.next()),
            chip,
            .draft(index: 0, summary: resetRoutine.summary, at: clock.next())
        ]
    }

    static func reply(now: Date) -> String {
        let dates = sessionDaysAgo.map { daysAgo in
            dayMonth.format(now.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60))
        }
        let kg = Int(stalledKg)
        return """
        Three sessions, same numbers:

        1. **\(kg) kg × 8, 8, 7** on \(dates[0])
        2. **\(kg) kg × 8, 8, 7** on \(dates[1])
        3. **\(kg) kg × 8, 7, 6** on \(dates[2]) — RPE 9 on the last set

        That's fatigue, not a ceiling. **Back off to \(resetKg.formatted()) kg**, rebuild on 3 × 5, \
        +2.5 kg every session you hit 5/5/5 — past \(kg) kg in three weeks.
        """
    }

    // MARK: - Drafts

    /// Names are the seed library's exact spellings (`DaGym/Resources/Seed/exercises.json`) —
    /// what `validate` would hand back — so the card shows what the store would save.
    static let resetRoutine = RoutineProposal(
        name: "Push A · Bench Reset",
        exercises: [
            CoachChatExerciseSpec(
                exerciseName: "Barbell Bench Press - Medium Grip",
                sets: sets(3, reps: 5, kg: resetKg, rpe: 8), restSeconds: 180,
                reason: "Down from \(Int(stalledKg)) kg so week one is 5/5/5 with a rep in hand."
            ),
            CoachChatExerciseSpec(
                exerciseName: "Pause Bench",
                sets: sets(2, reps: 3, kg: 65), restSeconds: 150,
                reason: "Your last set stalls off the chest; a one-second pause fixes that."
            ),
            CoachChatExerciseSpec(
                exerciseName: "Triceps Pushdown",
                sets: sets(3, reps: 12, kg: 25), restSeconds: 60,
                reason: "Lockout help; you leave reps here whenever bench is heavy."
            )
        ],
        rule: .linear
    )

    static let alternativeRationale =
        "Agree on the reset, but a lifter stalling on fatigue doesn't need a second bench variation. "
        + "Dips in place of the pause bench: same pressing pattern, self-limiting load, and the triceps "
        + "get their work without another bar set."

    static let alternativeRoutine = RoutineProposal(
        name: "Push A · Bench Reset",
        exercises: [
            CoachChatExerciseSpec(
                exerciseName: "Barbell Bench Press - Medium Grip",
                sets: sets(3, reps: 5, kg: resetKg, rpe: 8), restSeconds: 180,
                reason: "Same reset as Gemini's: \(resetKg.formatted()) kg for 5/5/5, then +2.5 kg."
            ),
            CoachChatExerciseSpec(
                exerciseName: "Dips - Chest Version",
                sets: sets(3, reps: 8), restSeconds: 120,
                reason: "Replaces the pause bench: pressing volume without a second heavy bar set."
            ),
            CoachChatExerciseSpec(
                exerciseName: "Triceps Pushdown",
                sets: sets(2, reps: 12, kg: 25), restSeconds: 60,
                reason: "One set fewer: dips already load the triceps."
            )
        ],
        rule: .linear,
        notes: "Three minutes between bench sets."
    )

    static var drafts: [CoachChatDraft] { [.routine(resetRoutine), .routine(alternativeRoutine)] }

    private static func sets(
        _ count: Int, reps: Int, kg: Double? = nil, rpe: Double? = nil
    ) -> [CoachChatSetSpec] {
        Array(repeating: CoachChatSetSpec(targetReps: reps, targetWeightKg: kg, rpe: rpe), count: count)
    }

    // MARK: - Reviewer chips

    private static func reviewerChips(clock: Clock) -> [CoachChatMessage] {
        var opener = CoachChatMessage.tool("review", at: clock.next())
        opener.text = "Second opinion · \(CoachChatConfiguration.displayName(forModelID: reviewerModelID))"
        opener.reviewIndex = 0
        var history = CoachChatMessage.tool(CoachChatToolName.getExerciseHistory.rawValue, at: clock.next())
        history.text = "Opus · \(history.text) · Barbell Bench Press - Medium Grip"
        history.reviewIndex = 0
        return [opener, history]
    }

    /// Timestamps a few seconds apart, so the thread reads as one sitting.
    private final class Clock {
        private(set) var now: Date

        init(start: Date) { now = start }

        func next() -> Date {
            now = now.addingTimeInterval(4)
            return now
        }
    }
}

private extension CoachChatUsage {
    mutating func add(promptTokens: Int, completionTokens: Int, model: String) {
        self.promptTokens += promptTokens
        self.completionTokens += completionTokens
        byModel[model] = CoachChatModelUsage(promptTokens: promptTokens, completionTokens: completionTokens)
    }
}
