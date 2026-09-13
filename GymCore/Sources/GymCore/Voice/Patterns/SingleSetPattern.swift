import Foundation

/// §4.5 pattern 11: the general single-set grammar, in either number order,
/// plus per-side, assistance, added-weight and bodyweight variants.
enum SingleSetPattern {
    private struct Modifiers {
        var kind: SetKind?
        var isPerSide: Bool
        var effort: Effort?
        var assistanceKg: Double?
        var addedKg: Double?
        var isBodyweightWord: Bool

        var isEmpty: Bool {
            kind == nil && effort == nil && assistanceKg == nil && addedKg == nil
                && !isPerSide && !isBodyweightWord
        }
    }

    static func match(_ originalWords: [String], context: ParseContext) -> ParseResult? {
        var words = originalWords
        let mods = extractModifiers(&words, context: context)

        let mentions = NumberScan.scan(words)
        let consumed = NumberScan.consumedIndices(mentions)
        let exercisePhrase = ExercisePhrase.extract(words, excluding: consumed)

        guard hasEnoughStructure(
            mentions: mentions, exercisePhrase: exercisePhrase, hasModifiers: !mods.isEmpty, words: words
        ) else { return nil }

        var reps: Int?
        var weightKg: Double?
        assignSlots(
            mentions: mentions, words: words, context: context, reps: &reps, weightKg: &weightKg
        )

        let (exercise, matchScore) = ExercisePhrase.resolve(exercisePhrase, in: context)
        var namedExercise = false
        if case .id = exercise { namedExercise = true }
        // A named exercise with reps and no load is bodyweight work; an unresolved
        // phrase is not evidence of anything, so it never flips the set.
        let autoBodyweight = mods.isBodyweightWord || (
            weightKg == nil && mods.addedKg == nil && mods.assistanceKg == nil && reps != nil
            && namedExercise
        )

        var unresolved: [Unresolved] = []
        if case .spoken = exercise { unresolved.append(.exerciseAmbiguous) }
        if reps == nil { unresolved.append(.missingReps) }

        let values = LogSetSpec.SetValues(
            reps: reps, weightKg: weightKg, assistanceKg: mods.assistanceKg, addedKg: mods.addedKg,
            isBodyweight: autoBodyweight
        )
        let spec = LogSetSpec(
            exercise: exercise, kind: mods.kind, sets: [values], effort: mods.effort,
            isPerSide: mods.isPerSide
        )
        let confidence = confidenceFor(
            reps: reps, weightKg: weightKg, addedKg: mods.addedKg,
            assistanceKg: mods.assistanceKg, isBodyweight: autoBodyweight
        ) * matchScore
        return ParseResult(
            commands: [.logSet(spec)], confidence: confidence, matchedPattern: "singleSet",
            unresolved: unresolved
        )
    }

    private static func extractModifiers(
        _ words: inout [String], context: ParseContext
    ) -> Modifiers {
        var mods = Modifiers(kind: nil, isPerSide: false, effort: nil, assistanceKg: nil,
                             addedKg: nil, isBodyweightWord: false)

        if let (foundKind, index) = SetKindWord.detect(words) {
            mods.kind = foundKind; words.remove(at: index)
        }
        if let index = words.firstIndex(of: "per-side") {
            mods.isPerSide = true; words.remove(at: index)
        }
        if let (foundEffort, range) = EffortExtraction.extract(words) {
            mods.effort = foundEffort; words.removeSubrange(range)
        }
        if let index = words.firstIndex(of: "minus"),
           let (value, range) = weightAfter(words, index: index, context: context) {
            mods.assistanceKg = value
            words.removeSubrange(range)
        }
        if let index = words.firstIndex(of: "with"),
           let (value, range) = weightAfter(words, index: index, context: context) {
            mods.addedKg = value
            words.removeSubrange(range)
        }
        if let index = words.firstIndex(of: "bodyweight") {
            mods.isBodyweightWord = true; words.remove(at: index)
        }
        return mods
    }

    /// The weight spoken after a trigger word at `index` ("minus twenty five",
    /// "with ten kilos"), and the trigger-through-unit range it occupies.
    private static func weightAfter(
        _ words: [String], index: Int, context: ParseContext
    ) -> (Double, Range<Int>)? {
        guard let (value, consumed) = NumberWords.parseBeforeReps(words, at: index + 1) else { return nil }
        var end = index + 1 + consumed
        var unit: UnitKind?
        if end < words.count, let attached = Tokenizer.unitKind(for: words[end]) {
            unit = attached; end += 1
        }
        return (UnitParser.weightKg(number: value, unit: unit, context: context), index..<end)
    }

    private static func hasEnoughStructure(
        mentions: [NumberMention], exercisePhrase: String?, hasModifiers: Bool, words: [String]
    ) -> Bool {
        guard !mentions.isEmpty else { return false }
        if mentions.count >= 2 { return true }
        if exercisePhrase != nil || hasModifiers { return true }
        guard let mention = mentions.first else { return false }
        if mention.unit != nil { return true }
        return NumberWords.repsFollows(words, at: mention.range.upperBound)
    }

    private static func assignSlots(
        mentions: [NumberMention], words: [String], context: ParseContext,
        reps: inout Int?, weightKg: inout Double?
    ) {
        func weight(_ mention: NumberMention) -> Double {
            UnitParser.weightKg(number: mention.value, unit: mention.unit, context: context)
        }
        guard mentions.count >= 2 else {
            guard let mention = mentions.first else { return }
            let followsReps = NumberWords.repsFollows(words, at: mention.range.upperBound)
            if mention.unit != nil {
                weightKg = weight(mention)
            } else if followsReps || mention.value <= VoiceGrammar.repsWeightCutoff {
                reps = Int(mention.value)
            } else {
                weightKg = context.unit.toKg(mention.value)
            }
            return
        }
        let first = mentions[0], second = mentions[1]
        let secondFollowsReps = NumberWords.repsFollows(words, at: second.range.upperBound)
        let firstFollowsReps = NumberWords.repsFollows(words, at: first.range.upperBound)
        let between = first.range.upperBound < second.range.lowerBound
            ? words[first.range.upperBound..<second.range.lowerBound] : ArraySlice<String>()

        if secondFollowsReps || between.contains("for") || between.contains("got") {
            weightKg = weight(first); reps = Int(second.value)
        } else if firstFollowsReps {
            reps = Int(first.value); weightKg = weight(second)
        } else if between.contains("at") || between.contains("to") {
            reps = Int(first.value); weightKg = weight(second)
        } else if first.unit != nil {
            weightKg = weight(first); reps = Int(second.value)
        } else {
            reps = Int(first.value); weightKg = weight(second)
        }
    }

    private static func confidenceFor(
        reps: Int?, weightKg: Double?, addedKg: Double?, assistanceKg: Double?, isBodyweight: Bool
    ) -> Double {
        if reps != nil && weightKg != nil { return 0.9 }
        if reps != nil && (addedKg != nil || assistanceKg != nil || isBodyweight) { return 0.85 }
        if reps != nil || weightKg != nil { return 0.8 }
        return 0.75
    }
}
