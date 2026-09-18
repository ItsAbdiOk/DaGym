import Foundation

/// Seeded exercises that show another seeded exercise's picture, because the two are the same
/// movement ("2 Handed Kettlebell Swing" → "Kettlebell Swing", "Deadlifts" → "Barbell Deadlift")
/// and only one of them has art or photographs. Hand-reviewed; the mapping lives in
/// `DaGym/Resources/Seed/exercise-media-aliases.json` and `scripts/propose-media-aliases.py`
/// proposes candidates for it. Every target has media of its own, and nothing is aliased more
/// than one hop (`ExerciseMediaTests` pins both).
///
/// Media only: the alias never touches the exercise's name, muscles or instructions. The credit
/// line under the hero follows the picture that is shown, so an alias onto illustrated art still
/// shows the art credit.
enum ExerciseMediaAliases {
    /// The seedID whose media `seedID` shows: the alias target when there is one, otherwise
    /// `seedID` itself.
    static func resolve(_ seedID: String) -> String {
        aliases[seedID] ?? seedID
    }

    /// Whether `seedID` shows another exercise's picture.
    static func isAliased(_ seedID: String) -> Bool {
        aliases[seedID] != nil
    }

    /// Every alias, source → target. Decoded once; the file is small.
    static let aliases: [String: String] = load()

    private static func load() -> [String: String] {
        guard
            let url = BundledSeedFile.url(forResource: "exercise-media-aliases"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }
}

/// Where the seed-adjacent JSON files live. XcodeGen may flatten `Resources/Seed` or keep it as
/// a subdirectory depending on how the group is generated, so both are tried, in this bundle and
/// then in every loaded bundle (the hosted test bundle sees the app's resources that way).
enum BundledSeedFile {
    static func url(forResource name: String) -> URL? {
        if let url = url(forResource: name, in: .main) { return url }
        for bundle in Bundle.allBundles {
            if let url = url(forResource: name, in: bundle) { return url }
        }
        return nil
    }

    private static func url(forResource name: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: "json", subdirectory: "Seed")
            ?? bundle.url(forResource: name, withExtension: "json")
    }
}
