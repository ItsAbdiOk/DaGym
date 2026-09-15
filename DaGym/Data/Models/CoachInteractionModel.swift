import Foundation
import SwiftData

/// One persisted Approve/Dismiss of a coach card (`GymCore.CoachInteraction`), keyed by the same
/// `(rule, fingerprint)` pair `CoachCard.fingerprint` computes — so `CoachEngine.cards(for:)`'s
/// cooldown window survives relaunch (plan: "dismissals and approvals must survive relaunch, so
/// the cooldown logic actually works"). Append-only from the UI's point of view: every Approve or
/// Dismiss inserts a fresh row rather than upserting one, and `WorkoutStore.coachInteractions()`
/// hands the whole history to the engine, which does its own cooldown-window filtering — this
/// model stores raw facts, not derived state.
@Model
final class CoachInteractionModel {
    var id = UUID()
    /// `GymCore.CoachRule.rawValue`.
    var rule: String = ""
    /// `GymCore.CoachCard.fingerprint` — identifies the evidence, not just the rule.
    var fingerprint: String = ""
    /// "dismissed" or "approved" (`GymCore.CoachInteraction.Outcome`).
    var outcome: String = "dismissed"
    var date = Date()

    init(
        id: UUID = UUID(), rule: String = "", fingerprint: String = "", outcome: String = "dismissed",
        date: Date = Date()
    ) {
        self.id = id
        self.rule = rule
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.date = date
    }
}
