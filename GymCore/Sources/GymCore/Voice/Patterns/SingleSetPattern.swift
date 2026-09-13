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
    }

    static func match(_ originalWords: [String], context: ParseContext) -> ParseResult? {
        var words = originalWords
        let mods = extractModifiers(&words, context: context)

        let mentions = NumberScan.scan(words)
        let consumed = NumberScan.consumedIndices(mentions)
        let exercisePhrase = ExercisePhrase.extract(words, excluding: consumed)

        let hasModifiers = mods.kind != nil || mods.effort != nil || mods.assistanceKg != nil
            || mods.addedKg != nil || mods.isPerSide
        guard hasEnoughStructure(
            mentions: mentions, exercisePhrase: exercisePhrase, hasModifiers: hasModifiers, words: words
        ) else { return nil }

        var reps: Int?
        var weightKg: Double?
        assignSlots(
            mentions: mentions, words: words, context: context, reps: &reps, weightKg: &weightKg
        )

        let autoBodyweight = mods.isBodyweightWord || (
            weightKg == nil && mods.addedKg == nil && mods.assistanceKg == nil && reps != nil
            && exercisePhrase != nil
        )

        let exercise = ExercisePhrase.resolve(exercisePhrase, in: context)
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
        )
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
        if let index = words.firstIndex(of: "minus"), index + 1 < words.count,
           let value = NumberWords.parseSingleWord(words[index + 1]) {
            mods.assistanceKg = context.unit.toKg(value)
            words.removeSubrange(index...(index + 1))
        }
        if let index = words.firstIndex(of: "with"), index + 1 < words.count,
           let (value, consumed) = NumberWords.parse(words, at: index + 1) {
            var end = index + 1 + consumed
            var unit: UnitKind?
            if end < words.count, let attached = Tokenizer.unitKind(for: words[end]) {
                unit = attached; end += 1
            }
            mods.addedKg = UnitParser.weightKg(number: value, unit: unit, context: context)
            words.removeSubrange(index..<end)
        }
        if let index = words.firstIndex(of: "bodyweight") {
            mods.isBodyweightWord = true; words.remove(at: index)
        }
        return mods
    }

    private static func hasEnoughStructure(
        mentions: [NumberMention], exercisePhrase: String?, hasModifiers: Bool, words: [String]
    ) -> Bool {
        guard !mentions.isEmpty else { return false }
        if mentions.count >= 2 { return true }
        if exercisePhrase != nil || hasModifiers { return true }
        guard let mention = mentions.first else { return false }
        if mention.unit != nil { return true }
        let followsReps = mention.range.upperBound < words.count
            && ["reps", "rep"].contains(words[mention.range.upperBound])
        return followsReps
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
            let followsReps = mention.range.upperBound < words.count
                && ["reps", "rep"].contains(words[mention.range.upperBound])
            if mention.unit != nil {
                weightKg = weight(mention)
            } else if followsReps || mention.value <= 50 {
                reps = Int(mention.value)
            } else {
                weightKg = context.unit.toKg(mention.value)
            }
            return
        }
        let first = mentions[0], second = mentions[1]
        let secondFollowsReps = second.range.upperBound < words.count
            && ["reps", "rep"].contains(words[second.range.upperBound])
        let firstFollowsReps = first.range.upperBound < words.count
            && ["reps", "rep"].contains(words[first.range.upperBound])
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
