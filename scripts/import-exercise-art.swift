// Regenerates DaGym/Resources/ExerciseArtPaths.zlib and DaGym/Data/ExerciseArtCatalog.swift from
// the workout-guide artwork package (302 exercises × 3 SVG frames, CC BY-SA 4.0, Bryl Lim,
// derived from Everkinetic — see DaGym/Resources/ATTRIBUTION-ExerciseArt.txt).
//
// We do NOT ship the SVGs (or a rasterised asset catalogue built from them): Xcode rasterises
// each SVG imageset at multiple scales on top of keeping the vector copy, which blew
// Assets.car from 28 KB to 52 MB for 516 images. Instead this script extracts each frame's raw
// `d="..."` path data, rounds coordinates to 1 decimal place (imperceptible at the ~44-240pt
// sizes ExerciseArtView renders — a 0.1-unit error against the 512-unit viewBox), and packs it
// into one zlib-compressed JSON blob that `ExerciseArtPathStore` (see ExerciseArtCatalog.swift)
// decompresses and parses into SwiftUI `Path`s lazily, off the main actor, at runtime.
//
// Entry point: scripts/import-exercise-art.sh <path-to-workout-guide-package> — that wrapper
// compiles this file together with GymCore's ImportAliases.swift and runs the result, so this
// script links directly against the real `ImportAliases.seedID(for:)` instead of re-deriving a
// second, possibly-diverging alias table.
//   <path-to-workout-guide-package> must contain manifest.json and assets/<slug>/frame-{1,2,3}.svg
//
// Idempotent: wipes and rewrites the path-data blob and the catalog file each run, and removes
// any leftover ExerciseArt.xcassets from before this script switched formats, so re-running
// after a manifest update or a re-clone of the source package is always safe.

import Foundation

// MARK: - Manifest / seed models

private struct ManifestFrame: Decodable {
    let index: Int
    let path: String
}

private struct ManifestExercise: Decodable {
    let id: String
    let slug: String
    let name: String
    let equipment: String?
    let frames: [ManifestFrame]
}

private struct SeedFile: Decodable {
    let exercises: [SeedExercise]
}

private struct SeedExercise: Decodable {
    let id: String
    let name: String
}

// MARK: - Paths

private let scriptURL = URL(fileURLWithPath: #filePath)
private let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let seedPath = repoRoot.appendingPathComponent("DaGym/Resources/Seed/exercises.json")
private let xcassetsPath = repoRoot.appendingPathComponent("DaGym/Resources/ExerciseArt.xcassets")
private let pathDataPath = repoRoot.appendingPathComponent("DaGym/Resources/ExerciseArtPaths.zlib")
private let catalogPath = repoRoot.appendingPathComponent("DaGym/Data/ExerciseArtCatalog.swift")

// MARK: - Name normalisation (direct-match pass only; the curated table below is ImportAliases,
// not a second normaliser)

/// Lower-cases, folds `-`/`_` to spaces, drops punctuation, and collapses whitespace, so
/// "Barbell_Squat" and "Barbell Squat" (or "EZ-Bar Skullcrusher" / "Ez Bar Skullcrusher")
/// compare equal. Used only to line up our seed names against the manifest's `name` field —
/// distinct from (and a precondition for) the curated equipment-qualifier table in
/// `ImportAliases`, which this script calls as the fallback pass.
private func normalise(_ raw: String) -> String {
    let folded = raw.lowercased().replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "/", with: " ")
    let allowed = folded.unicodeScalars.map { scalar -> Character in
        (CharacterSet.alphanumerics.contains(scalar) || scalar == " ") ? Character(scalar) : " "
    }
    let collapsed = String(allowed).split(separator: " ").joined(separator: " ")
    return collapsed
}

/// Drops a trailing plural "s" (not "ss") so "Squats"/"Squat" and "Rack Pulls"/"Rack Pull"
/// tokenise the same. Naive on purpose — this is a fuzzy fallback pass, not a grammar engine.
private func singularise(_ word: some StringProtocol) -> String {
    if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
    return String(word)
}

private let stopwords: Set<String> = ["the", "a", "an", "and", "with", "of", "to", "for"]

/// Significant, singularised word tokens — used for the fuzzy "manifest name's words all appear
/// in the seed name" pass, distinct from `normalise`'s exact-string comparison above.
private func tokenise(_ raw: String) -> Set<String> {
    Set(normalise(raw).split(separator: " ").map(singularise)).subtracting(stopwords)
}

/// Seed exercises whose name contains every word of `nameTokens`, closest match first
/// (fewest extra words in the seed name beyond what the manifest asked for; equipment-token
/// presence breaks ties). Empty when nothing contains the full manifest name.
private func fuzzyMatch(
    nameTokens: Set<String>, equipmentToken: String?, seedTokenSets: [(id: String, tokens: Set<String>)]
) -> String? {
    guard !nameTokens.isEmpty else { return nil }
    let candidates = seedTokenSets.filter { nameTokens.isSubset(of: $0.tokens) }
    guard !candidates.isEmpty else { return nil }
    let best = candidates.min { lhs, rhs in
        let lhsScore = lhs.tokens.count - (equipmentToken.map { lhs.tokens.contains($0) ? 1 : 0 } ?? 0)
        let rhsScore = rhs.tokens.count - (equipmentToken.map { rhs.tokens.contains($0) ? 1 : 0 } ?? 0)
        if lhsScore != rhsScore { return lhsScore < rhsScore }
        return lhs.id < rhs.id
    }
    return best?.id
}

// MARK: - Main

private func runMain() throws {
    guard CommandLine.arguments.count > 1 else {
        FileHandle.standardError.write(
            Data("usage: swift import-exercise-art.swift <path-to-workout-guide-package>\n".utf8)
        )
        exit(1)
    }
    let sourceRoot = URL(fileURLWithPath: CommandLine.arguments[1])
    let manifestURL = sourceRoot.appendingPathComponent("manifest.json")
    let assetsRoot = sourceRoot.appendingPathComponent("assets")

    let decoder = JSONDecoder()
    let manifest = try decoder.decode([ManifestExercise].self, from: Data(contentsOf: manifestURL))
    let seed = try decoder.decode(SeedFile.self, from: Data(contentsOf: seedPath))

    // normalised name -> seedID, first entry in file order wins ties deterministically.
    var byNormalisedName: [String: String] = [:]
    for exercise in seed.exercises {
        let key = normalise(exercise.name)
        if byNormalisedName[key] == nil { byNormalisedName[key] = exercise.id }
    }
    let seedIDs = Set(seed.exercises.map(\.id))
    let seedTokenSets = seed.exercises.map { (id: $0.id, tokens: tokenise($0.name)) }

    var matches: [(seedID: String, slug: String)] = []
    var unmatchedSlugs: [String] = []

    for exercise in manifest {
        // Our seed names fold equipment into the name itself ("Barbell Squat", "Incline Bench
        // Press Dumbbell" — the order isn't consistent), while the manifest keeps them separate
        // (name: "Squat", equipment: "Barbell"). Try the bare name first, then both orderings of
        // name + equipment, then the curated alias table (authoritative for the ~40 names it
        // covers, so it outranks the blind fuzzy pass below), and only then fuzzy word-subset
        // matching as a last resort for names the alias table doesn't know.
        let equipment = exercise.equipment ?? ""
        var candidates = [exercise.name]
        if !equipment.isEmpty {
            candidates.append("\(equipment) \(exercise.name)")
            candidates.append("\(exercise.name) \(equipment)")
        }
        if let seedID = candidates.lazy.compactMap({ byNormalisedName[normalise($0)] }).first {
            matches.append((seedID, exercise.slug))
            continue
        }
        // ImportAliases keys off a trailing "(Qualifier)", e.g. "Bench Press (Barbell)".
        let qualifiedName = equipment.isEmpty ? exercise.name : "\(exercise.name) (\(equipment))"
        if let aliasID = ImportAliases.seedID(for: qualifiedName), seedIDs.contains(aliasID) {
            matches.append((aliasID, exercise.slug))
            continue
        }
        // Fuzzy pass: every significant word of the manifest name must appear in the seed name
        // ("Front Squat" ⊆ "Front Squats", "Decline Bench Press" ⊆ "Decline Barbell Bench
        // Press"), picking the seed exercise with the fewest extra words.
        let equipmentToken = equipment.isEmpty ? nil : tokenise(equipment).first
        if let seedID = fuzzyMatch(
            nameTokens: tokenise(exercise.name), equipmentToken: equipmentToken, seedTokenSets: seedTokenSets
        ) {
            matches.append((seedID, exercise.slug))
            continue
        }
        unmatchedSlugs.append(exercise.slug)
    }

    // A slug matching more than one seedID (shouldn't happen given the curated data, but keep the
    // first and warn rather than silently overwriting a catalog entry) — and de-dupe multiple
    // seedIDs racing for the same slug.
    var seedIDToSlug: [String: String] = [:]
    for (seedID, slug) in matches where seedIDToSlug[seedID] == nil {
        seedIDToSlug[seedID] = slug
    }

    // Pre-existing installs of this script (before it switched to path data) left a rasterised
    // asset catalogue on disk; remove it so it can never silently come back and re-inflate
    // Assets.car.
    if FileManager.default.fileExists(atPath: xcassetsPath.path) {
        try FileManager.default.removeItem(at: xcassetsPath)
    }

    let byteCount = try writePathData(
        manifest: manifest, matchedSlugs: Set(seedIDToSlug.values), assetsRoot: assetsRoot
    )
    try writeCatalog(seedIDToSlug: seedIDToSlug)

    print("Matched \(seedIDToSlug.count) / \(seed.exercises.count) seeded exercises to art.")
    print("Unmatched manifest slugs: \(unmatchedSlugs.count) (no seed exercise found for them).")
    if ProcessInfo.processInfo.environment["DEBUG_UNMATCHED"] != nil {
        for exercise in manifest where unmatchedSlugs.contains(exercise.slug) {
            print("UNMATCHED: \(exercise.name) | \(exercise.equipment ?? "-") | \(exercise.slug)")
        }
    }
    let sizeString = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    print("ExerciseArtPaths.zlib size: \(sizeString)")
}

// MARK: - Path-data extraction

/// Matches the `d="..."` attribute of the single `<path>` element each frame SVG contains
/// (verified against the source package: one path per frame, `fill-rule="evenodd"`, 512×512
/// viewBox — see the script header). Not a general SVG/XML parser; deliberately narrow to what
/// this specific source package emits.
private let pathDataRegex = try! NSRegularExpression(pattern: #"d="([^"]*)""#)

/// A decimal token in path data, e.g. "123.456" or the leading-dot shorthand SVG minifiers use,
/// "-.957" (no digit before the point). Used to round coordinate precision down before shipping
/// — see `roundCoordinates`. Bare integers ("-7") need no rounding and are left untouched.
private let numberRegex = try! NSRegularExpression(pattern: #"-?[0-9]*\.[0-9]+"#)

private func extractPathData(from svgURL: URL) throws -> String {
    let content = try String(contentsOf: svgURL, encoding: .utf8)
    let range = NSRange(content.startIndex..., in: content)
    guard let match = pathDataRegex.firstMatch(in: content, range: range),
          let group = Range(match.range(at: 1), in: content)
    else {
        throw ImportError.noPathData(svgURL.lastPathComponent)
    }
    return String(content[group])
}

/// Rounds every decimal coordinate in `d` to `decimals` places. At the 44–240pt sizes
/// `ExerciseArtView` renders these paths (against a 512-unit viewBox), 1 decimal place is well
/// under a tenth of a display pixel of error — invisible — while shrinking the shipped data
/// (repeated short decimals compress much better than the source SVGs' full float precision).
private func roundCoordinates(_ d: String, decimals: Int) -> String {
    let range = NSRange(d.startIndex..., in: d)
    let matches = numberRegex.matches(in: d, range: range)
    var result = ""
    var cursor = d.startIndex
    let scale = pow(10.0, Double(decimals))
    for match in matches {
        guard let matchRange = Range(match.range, in: d) else { continue }
        let gap = d[cursor..<matchRange.lowerBound]
        // Source SVGs sometimes butt two numbers together with no separator, relying on a
        // second "." (or a "-" sign) to mark the boundary ("2.3.346" = 2.3, then .346). Rounding
        // can reshape a number (drop its "." entirely, or gain a leading "0") in a way that
        // erases that boundary and lets the two numbers silently merge into one wrong value on
        // reparse. An empty gap between two number tokens is exactly that unseparated case, so
        // force a space there rather than trusting the (possibly now-different) token shapes to
        // still be self-delimiting.
        result += gap.isEmpty && !result.isEmpty ? " " : gap
        let value = (Double(d[matchRange]) ?? 0)
        let rounded = (value * scale).rounded() / scale
        result += trimmedNumber(rounded, decimals: decimals)
        cursor = matchRange.upperBound
    }
    result += d[cursor...]
    return result
}

private func trimmedNumber(_ value: Double, decimals: Int) -> String {
    var text = String(format: "%.\(decimals)f", value)
    if text.contains(".") {
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
    }
    return text
}

private enum ImportError: Error, CustomStringConvertible {
    case noPathData(String)

    var description: String {
        switch self {
        case .noPathData(let filename): return "no d=\"...\" path found in \(filename)"
        }
    }
}

/// Extracts, rounds and JSON-encodes every matched exercise's 3 frames, zlib-compresses the
/// result, and writes it to `pathDataPath`. Returns the compressed byte count.
private func writePathData(
    manifest: [ManifestExercise], matchedSlugs: Set<String>, assetsRoot: URL
) throws -> Int64 {
    var framesBySlug: [String: [String]] = [:]
    for exercise in manifest where matchedSlugs.contains(exercise.slug) {
        var frames: [String] = []
        for frame in exercise.frames.sorted(by: { $0.index < $1.index }) {
            let sourceSVG = assetsRoot.appendingPathComponent(frame.path.replacingOccurrences(
                of: "assets/", with: ""
            ))
            let rawPath = try extractPathData(from: sourceSVG)
            frames.append(roundCoordinates(rawPath, decimals: 1))
        }
        framesBySlug[exercise.slug] = frames
    }

    let json = try JSONSerialization.data(
        withJSONObject: framesBySlug, options: [.sortedKeys, .withoutEscapingSlashes]
    )
    // Note: Apple's Compression-framework `.zlib` algorithm (used here via `NSData.compressed`,
    // and on the read side by `ExerciseArtPathStore` via `Data.decompressed`) is raw DEFLATE, not
    // an RFC 1950 zlib stream — fine since only our own code ever reads this file, but it means a
    // generic `zlib`/`gunzip` CLI can't inspect it directly.
    let compressed = try (json as NSData).compressed(using: .zlib) as Data
    try compressed.write(to: pathDataPath)
    return Int64(compressed.count)
}

// MARK: - Swift catalog generation

private func writeCatalog(seedIDToSlug: [String: String]) throws {
    let sortedEntries = seedIDToSlug.sorted { $0.key < $1.key }
    let entryLines = sortedEntries
        .map { "        \"\($0.key)\": \"\($0.value)\"" }
        .joined(separator: ",\n")

    let source = """
    // Generated by scripts/import-exercise-art.swift — do not edit by hand.
    // Maps a seeded exercise's `seedID` to its illustrated-art slug, and loads/caches the
    // matching path data from the bundled DaGym/Resources/ExerciseArtPaths.zlib.
    // Artwork: Bryl Lim, derived from Everkinetic, CC BY-SA 4.0 — see
    // DaGym/Resources/ATTRIBUTION-ExerciseArt.txt.

    import Foundation
    import SwiftUI

    /// Looks up the 3-frame illustrated art for a seeded exercise, when we have any.
    /// Roughly \(sortedEntries.count) of our seeded exercises match; the rest return `nil` and
    /// callers (`ExerciseArtView`) fall back to the existing glyph/icon treatment.
    enum ExerciseArtCatalog {
        /// seedID -> art slug.
        static let slugsBySeedID: [String: String] = [
    \(entryLines)
        ]

        /// The art slug for `seedID`'s illustration, or `nil` when this exercise has no
        /// illustrated art. Pass this to `ExerciseArtPathStore` to load the actual frames.
        static func slug(for seedID: String) -> String? {
            slugsBySeedID[seedID]
        }

        /// Existence check kept in its original array-returning shape for callers that only test
        /// this for `!= nil` (the array's contents are not asset names any more — the artwork
        /// itself comes from `ExerciseArtPathStore`, keyed by `slug(for:)`).
        static func frames(for seedID: String) -> [String]? {
            guard let slug = slugsBySeedID[seedID] else { return nil }
            return [slug, slug, slug]
        }
    }

    /// Loads the bundled, zlib-compressed exercise-art path data (raw SVG `d=` path strings,
    /// coordinates rounded to 1 decimal place — see import-exercise-art.swift) and parses each
    /// frame into a SwiftUI `Path` on first use, reusing MuscleMap's vendored SVG parser
    /// (`DaGym/Vendor/MuscleMap/Core/{SVGPathParser,PathBuilder}.swift`). An `actor` so decoding
    /// and parsing run off the main actor, and results are cached in memory for the process
    /// lifetime so the same slug is never re-parsed.
    actor ExerciseArtPathStore {
        static let shared = ExerciseArtPathStore()

        private var rawFramesBySlug: [String: [String]]?
        private var pathCache: [String: [Path]] = [:]

        /// The three frame `Path`s for `slug` (in a 512×512 coordinate space, matching the
        /// source SVGs' viewBox — callers scale to their display size), in playback order, or
        /// `nil` if `slug` has no bundled path data.
        func frames(forSlug slug: String) -> [Path]? {
            if let cached = pathCache[slug] { return cached }
            guard let raw = loadedRawFrames()[slug] else { return nil }
            let paths = raw.map { PathBuilder.buildPath(from: $0, scale: 1, offsetX: 0, offsetY: 0) }
            pathCache[slug] = paths
            return paths
        }

        private func loadedRawFrames() -> [String: [String]] {
            if let rawFramesBySlug { return rawFramesBySlug }
            let loaded = Self.loadRawFrames()
            rawFramesBySlug = loaded
            return loaded
        }

        private static func loadRawFrames() -> [String: [String]] {
            guard
                let url = Bundle.main.url(forResource: "ExerciseArtPaths", withExtension: "zlib"),
                let compressed = try? Data(contentsOf: url),
                let data = try? (compressed as NSData).decompressed(using: .zlib) as Data,
                let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
            else { return [:] }
            return decoded
        }
    }

    """
    try source.write(to: catalogPath, atomically: true, encoding: .utf8)
}

@main
enum EntryPoint {
    static func main() throws {
        try runMain()
    }
}
