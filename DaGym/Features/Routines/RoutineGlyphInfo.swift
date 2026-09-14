import Foundation

/// A routine's glyph (name + `RoutineGlyph`'s two inputs), captured alongside a workout so a
/// finished session's group headers and a live session's Live Activity can render it without
/// re-reading the routine — which may have changed its glyph, or been deleted, since. See
/// `WorkoutDetail.routineGlyphs` and `WorkoutSession.routineGlyphs`.
struct RoutineGlyphInfo: Hashable {
    var name: String
    var symbolName: String
    var tint: String

    /// Shown for a group/session whose routine no longer exists — same fallback
    /// `RoutineTint.named` uses for an unrecognised tint.
    static let deletedRoutine = RoutineGlyphInfo(name: "Routine", symbolName: "dumbbell", tint: "coral")
}
