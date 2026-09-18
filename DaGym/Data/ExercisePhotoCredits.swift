import Foundation

/// Who to credit for a bundled exercise photograph that did not come from free-exercise-db.
///
/// The free-exercise-db pairs are public domain and carry no caption. Everything imported by
/// `scripts/import-exercise-photos-extra.py` (wger.de, OpenTraining, Wikimedia Commons) is
/// listed in `DaGym/Resources/Seed/exercise-photo-credits.json` with its author and licence,
/// and the CC BY / CC BY-SA ones owe an on-screen credit — `captionLine` is that line. CC0 and
/// public-domain images are listed for traceability but caption nothing, like the rest.
struct ExercisePhotoCredit: Decodable, Equatable, Sendable {
    var source: String
    var author: String
    var licence: String
    var licenceURL: String
    var sourceURL: String
    var frames: [String]

    /// "Photo: Everkinetic · CC BY-SA 3.0", or `nil` when the licence asks for no attribution.
    var captionLine: String? {
        guard requiresAttribution else { return nil }
        return "Photo: \(author) · \(licence)"
    }

    /// Public-domain dedications carry no attribution condition; every CC BY / CC BY-SA
    /// licence does.
    var requiresAttribution: Bool {
        licence.hasPrefix("CC BY")
    }
}

enum ExercisePhotoCredits {
    /// The credit for `seedID`'s bundled photograph, or `nil` for a free-exercise-db pair (and
    /// for anything without photographs at all). Pass the *resolved* seedID — the one whose
    /// picture is on screen — not an alias.
    static func credit(for seedID: String) -> ExercisePhotoCredit? {
        credits[seedID]
    }

    /// Every credited photograph, by seedID. Decoded once.
    static let credits: [String: ExercisePhotoCredit] = load()

    private static func load() -> [String: ExercisePhotoCredit] {
        guard
            let url = BundledSeedFile.url(forResource: "exercise-photo-credits"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: ExercisePhotoCredit].self, from: data)
        else { return [:] }
        return decoded
    }
}
