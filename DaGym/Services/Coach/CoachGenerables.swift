import Foundation
import GymCore

#if canImport(FoundationModels)
import FoundationModels

/// The wire shapes Apple's on-device model fills in — one `@Generable` mirror per feature
/// result. They live here (not in GymCore, which can't import FoundationModels) and are
/// converted to the plain GymCore structs the validators take before anything else sees them.
///
/// Closed choices are expressed as **indexes into the list the prompt showed** (a candidate
/// number, a pool number, a lift number) rather than free-text ids: the model is far more
/// reliable at "pick 2" than at copying a UUID, and the validator still rejects any index that
/// doesn't map onto the list it was given.

@Generable(description: "One short sentence and the ids of the facts it rests on")
struct GeneratedClaim {
    @Guide(description: "One short sentence, no numbers")
    var text: String
    @Guide(description: "Ids of the facts this sentence rests on, copied exactly")
    var citedFactIDs: [String]
}

@Generable(description: "A short debrief of one gym session")
struct GeneratedDebrief {
    @Guide(description: "Overall session score", .range(1...10))
    var score: Int
    @Guide(description: "What went well", .maximumCount(3))
    var wentWell: [GeneratedClaim]
    @Guide(description: "What to watch", .maximumCount(3))
    var watch: [GeneratedClaim]
    @Guide(description: "What to try next session", .maximumCount(3))
    var tryNext: [GeneratedClaim]
}

@Generable(description: "One allowed replacement, by its number in the list")
struct GeneratedRankedPick {
    @Guide(description: "Number of the replacement in the allowed list", .range(1...3))
    var index: Int
    @Guide(description: "One line on why this pick fits the reason")
    var why: String
}

@Generable(description: "The allowed replacements, best first")
struct GeneratedRanking {
    @Guide(description: "Best first, each replacement at most once", .maximumCount(3))
    var picks: [GeneratedRankedPick]
}

@Generable(description: "One exercise chosen for one slot")
struct GeneratedSlotPick {
    @Guide(description: "The slot id exactly as given, e.g. d1s2")
    var slotID: String
    @Guide(description: "Number of the exercise in the pool", .range(1...60))
    var poolIndex: Int
}

@Generable(description: "A filled-in training program")
struct GeneratedProgram {
    @Guide(description: "A short program name, under 40 characters")
    var name: String
    @Guide(description: "One pick for every slot")
    var picks: [GeneratedSlotPick]
}

@Generable(description: "The kind of change proposed")
enum GeneratedChangeKind {
    case deloadLift, addExercise, swapExercise, changeRepRange, changeProgressionRule, moveRestDay
}

@Generable(description: "A progression rule")
enum GeneratedProgressionKind {
    case linear, doubleProgression
}

@Generable(description: "One proposed change with its evidence")
struct GeneratedChange {
    var kind: GeneratedChangeKind
    @Guide(description: "Lift number from the programme list (L1 = 1), 0 when no lift")
    var lift: Int
    @Guide(description: "Pool number (P1 = 1) to add or swap to, 0 when none")
    var pool: Int
    @Guide(description: "Rep range low end for changeRepRange or doubleProgression, else 0", .range(0...30))
    var repLow: Int
    @Guide(description: "Rep range high end, else 0", .range(0...30))
    var repHigh: Int
    @Guide(description: "Progression rule for changeProgressionRule")
    var progressionRule: GeneratedProgressionKind?
    @Guide(description: "For moveRestDay: weekday to stop training, 1 = Sunday … 7 = Saturday, else 0")
    var fromWeekday: Int
    @Guide(description: "For moveRestDay: weekday to train instead, 1 = Sunday … 7 = Saturday, else 0")
    var toWeekday: Int
    @Guide(description: "One sentence of evidence, no numbers")
    var evidence: String
    @Guide(description: "Ids of the facts this change rests on, copied exactly")
    var citedFactIDs: [String]
}

@Generable(description: "Up to three proposed changes")
struct GeneratedReview {
    @Guide(description: "Proposed changes, most important first", .maximumCount(3))
    var changes: [GeneratedChange]
}

// MARK: - Conversion to the plain GymCore shapes the validators take

extension GeneratedClaim {
    var claim: CoachClaim { CoachClaim(text: text, citedFactIDs: citedFactIDs) }
}

extension GeneratedDebrief {
    var debrief: SessionDebrief {
        SessionDebrief(
            score: score, wentWell: wentWell.map(\.claim), watch: watch.map(\.claim),
            tryNext: tryNext.map(\.claim)
        )
    }
}

extension GeneratedDebrief.PartiallyGenerated {
    /// A provisional debrief from a streaming snapshot: whatever has arrived so far, an unscored
    /// snapshot reading as a middling 5 until the score lands. Only shown after the validator
    /// has filtered it, so a half-written claim without its citations isn't on screen yet.
    var provisionalDebrief: SessionDebrief {
        func claims(_ partial: [GeneratedClaim.PartiallyGenerated]?) -> [CoachClaim] {
            (partial ?? []).compactMap { item in
                guard let text = item.text else { return nil }
                return CoachClaim(text: text, citedFactIDs: item.citedFactIDs ?? [])
            }
        }
        return SessionDebrief(
            score: score ?? 5, wentWell: claims(wentWell), watch: claims(watch), tryNext: claims(tryNext)
        )
    }
}

extension GeneratedRanking {
    func ranked(candidates: [ScoredSubstitute]) -> [RankedSubstitute] {
        picks.compactMap { pick in
            guard candidates.indices.contains(pick.index - 1) else { return nil }
            return RankedSubstitute(candidateID: candidates[pick.index - 1].id, why: pick.why)
        }
    }
}

extension GeneratedProgram {
    func draft(pool: [SubstitutionCandidate]) -> ProgramDraft {
        let picks = picks.compactMap { pick -> ProgramPick? in
            guard pool.indices.contains(pick.poolIndex - 1) else { return nil }
            return ProgramPick(slotID: pick.slotID, exerciseID: pool[pick.poolIndex - 1].id)
        }
        return ProgramDraft(name: name, picks: picks)
    }
}

extension GeneratedChange {
    /// Nil when the numbers don't point at anything in the digest — the validator would refuse
    /// it anyway, but a `ReviewChange` can't even be built without real ids.
    func proposal(digest: TrainingDigest) -> ReviewProposal? {
        let liftID = digest.lifts.indices.contains(lift - 1) ? digest.lifts[lift - 1].id : nil
        let poolID = digest.pool.indices.contains(pool - 1) ? digest.pool[pool - 1].id : nil
        let change: ReviewChange?
        switch kind {
        case .deloadLift:
            change = liftID.map(ReviewChange.deloadLift)
        case .addExercise:
            change = poolID.map(ReviewChange.addExercise)
        case .swapExercise:
            if let liftID, let poolID {
                change = .swapExercise(from: liftID, to: poolID)
            } else {
                change = nil
            }
        case .changeRepRange:
            change = liftID.map { .changeRepRange(exerciseID: $0, low: repLow, high: repHigh) }
        case .changeProgressionRule:
            // The lift's own step, not a hard-coded 2.5 kg: a squat climbs by 5 kg, a lb lifter
            // by a round 5 lb.
            let increment = digest.lifts.indices.contains(lift - 1)
                ? digest.lifts[lift - 1].incrementKg : TrainingConstants.defaultUpperBodyIncrementKg
            let rule: ProgressionRule
            switch progressionRule {
            case .linear, .none: rule = .linear(incrementKg: increment)
            case .doubleProgression:
                let low = repLow > 0 ? repLow : 8
                let high = repHigh > 0 ? repHigh : 12
                rule = .doubleProgression(low: low, high: high, incrementKg: increment)
            }
            change = liftID.map { .changeProgressionRule(exerciseID: $0, rule: rule) }
        case .moveRestDay:
            if let from = Weekday(rawValue: fromWeekday), let to = Weekday(rawValue: toWeekday) {
                change = .moveRestDay(from: from, to: to)
            } else {
                change = nil
            }
        }
        return change.map { change in
            ReviewProposal(change: change, claim: CoachClaim(text: evidence, citedFactIDs: citedFactIDs))
        }
    }
}
#endif
