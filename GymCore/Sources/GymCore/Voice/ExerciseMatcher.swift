import Foundation

/// Fuzzy-matches a spoken exercise phrase against the library, boosted by
/// session membership, favourites, equipment words, and a curated/learned
/// alias table. Never guesses between two close exercises — see `resolve`.
public enum ExerciseMatcher {
    /// Score at or above which a single best match auto-resolves.
    public static let threshold = 0.82
    /// Minimum lead over the runner-up for a single best match to auto-resolve.
    public static let margin = 0.06
    /// The most session/favourite boosts may add when the phrase is a strict
    /// subset of the name ("bench" → "Bench Dips"): a one-word shorthand needs
    /// an alias, not a lucky prefix, to auto-resolve.
    private static let subsetBoostCap = 0.05

    /// The one auto-resolve rule, shared with the validator's gate on `.spoken`.
    public static func isConfident(best: Double, runnerUp: Double) -> Bool {
        best >= 1.0 || (best >= threshold && (best - runnerUp) >= margin)
    }

    private static let equipmentWords: Set<String> = ["dumbbell", "barbell", "cable", "machine", "band"]
    private static let qualifierWords: Set<String> = [
        "incline", "decline", "seated", "standing", "one-arm", "single-arm", "close-grip",
        "wide-grip", "reverse", "underhand", "overhand", "assisted", "smith"
    ]

    /// All candidates, best score first.
    public static func match(_ phrase: String, in context: ParseContext) -> [ExerciseMatch] {
        let normalizedPhrase = normalize(phrase)
        if let id = context.aliases[normalizedPhrase] {
            let allCandidates = context.sessionExercises + context.library
            let name = allCandidates.first(where: { $0.id == id })?.name ?? phrase
            return [ExerciseMatch(id: id, name: name, score: 1.0)]
        }

        var seen = Set<UUID>()
        var scored: [ExerciseMatch] = []
        for candidate in context.sessionExercises + context.library {
            guard seen.insert(candidate.id).inserted else { continue }
            let candidateScore = score(phrase: normalizedPhrase, candidate: candidate)
            scored.append(ExerciseMatch(id: candidate.id, name: candidate.name, score: candidateScore))
        }
        return scored.sorted { $0.score > $1.score }
    }

    /// A single `.id` when the best match clears threshold and margin over the
    /// runner-up; otherwise `.spoken` with the top 3 candidates for disambiguation.
    public static func resolve(_ phrase: String, in context: ParseContext) -> ExerciseRef {
        resolveScored(phrase, in: context).ref
    }

    /// `resolve` plus the best match's score, which the parser folds into
    /// `ParseResult.confidence` (§4.7) so a fuzzy `.id` never looks as sure as an alias hit.
    public static func resolveScored(
        _ phrase: String, in context: ParseContext
    ) -> (ref: ExerciseRef, score: Double) {
        let matches = match(phrase, in: context)
        guard let best = matches.first, best.score > 0 else {
            return (.spoken(phrase, candidates: Array(matches.prefix(3))), 0)
        }
        let runnerUp = matches.count > 1 ? matches[1].score : 0
        if isConfident(best: best.score, runnerUp: runnerUp) {
            return (.id(best.id), best.score)
        }
        return (.spoken(phrase, candidates: Array(matches.prefix(3))), best.score)
    }

    static func score(phrase: String, candidate: ParseContext.ExerciseCandidate) -> Double {
        let phraseTokens = tokens(phrase)
        let nameTokens = tokens(candidate.name)
        let normalizedName = normalize(candidate.name)
        var value = 0.6 * tokenSetRatio(phraseTokens, nameTokens) + 0.4 * jaroWinkler(phrase, normalizedName)
        var boost = 0.0
        if candidate.isInSession { boost += 0.10 }
        if candidate.isFavorite { boost += 0.05 }
        if Set(phraseTokens).isStrictSubset(of: Set(nameTokens)) { boost = min(boost, subsetBoostCap) }
        value += boost
        let phraseHasEquipment = !equipmentWords.isDisjoint(with: Set(phraseTokens))
        let nameHasEquipment = !equipmentWords.isDisjoint(with: Set(nameTokens))
        if let equipment = candidate.equipment?.lowercased(), phraseTokens.contains(equipment) {
            value += 0.03
        } else if phraseHasEquipment && nameHasEquipment {
            value += 0.03
        }
        let missingQualifiers = nameTokens.filter {
            qualifierWords.contains($0) && !phraseTokens.contains($0)
        }
        value -= 0.05 * Double(missingQualifiers.count)
        return max(0, min(1, value))
    }

    private static func normalize(_ text: String) -> String {
        Tokenizer.words(text).joined(separator: " ")
    }

    private static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map { stem(String($0)) }
    }

    private static func stem(_ word: String) -> String {
        if word.hasSuffix("es"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), word.count > 3, !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// Dice coefficient over token sets — a cheap stand-in for fuzzywuzzy's
    /// token_set_ratio that's order- and duplicate-insensitive.
    static func tokenSetRatio(_ first: [String], _ second: [String]) -> Double {
        let setA = Set(first), setB = Set(second)
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        let common = setA.intersection(setB).count
        return 2.0 * Double(common) / Double(setA.count + setB.count)
    }

    /// Standard Jaro-Winkler string similarity, 0…1.
    static func jaroWinkler(_ first: String, _ second: String) -> Double {
        let jaro = jaroSimilarity(first, second)
        guard jaro > 0.7 else { return jaro }
        let firstChars = Array(first), secondChars = Array(second)
        var prefix = 0
        for index in 0..<min(4, firstChars.count, secondChars.count)
            where firstChars[index] == secondChars[index] {
            prefix += 1
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

    private static func jaroSimilarity(_ first: String, _ second: String) -> Double {
        let firstChars = Array(first), secondChars = Array(second)
        if firstChars.isEmpty && secondChars.isEmpty { return 1 }
        if firstChars.isEmpty || secondChars.isEmpty { return 0 }
        let matchDistance = max(firstChars.count, secondChars.count) / 2 - 1
        var firstMatches = [Bool](repeating: false, count: firstChars.count)
        var secondMatches = [Bool](repeating: false, count: secondChars.count)
        var matches = 0
        for index in 0..<firstChars.count {
            let lowerBound = max(0, index - matchDistance)
            let upperBound = min(index + matchDistance + 1, secondChars.count)
            guard lowerBound < upperBound else { continue }
            for other in lowerBound..<upperBound
                where !secondMatches[other] && firstChars[index] == secondChars[other] {
                firstMatches[index] = true; secondMatches[other] = true; matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        var transpositions = 0
        var cursor = 0
        for index in 0..<firstChars.count where firstMatches[index] {
            while !secondMatches[cursor] { cursor += 1 }
            if firstChars[index] != secondChars[cursor] { transpositions += 1 }
            cursor += 1
        }
        let matchCount = Double(matches)
        return (
            matchCount / Double(firstChars.count) + matchCount / Double(secondChars.count)
                + (matchCount - Double(transpositions / 2)) / matchCount
        ) / 3
    }
}
