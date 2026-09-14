import SwiftUI

/// The tints a routine glyph can take. Raw values are what `RoutineModel.tint` stores, so
/// renaming a case is a data migration — add, don't rename. `coral` follows the user's accent.
enum RoutineTint: String, CaseIterable, Identifiable {
    case coral, gold, violet, ice, green, red

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coral: "Coral"
        case .gold: "Gold"
        case .violet: "Violet"
        case .ice: "Ice"
        case .green: "Green"
        case .red: "Red"
        }
    }

    var color: Color {
        switch self {
        case .coral: DGColor.coral
        case .gold: DGColor.prGold
        case .violet: DGColor.aiViolet
        case .ice: DGColor.info
        case .green: DGColor.success
        case .red: DGColor.danger
        }
    }

    /// Falls back to coral for a key this build doesn't know (a newer app on another device).
    static func named(_ raw: String) -> RoutineTint { RoutineTint(rawValue: raw) ?? .coral }
}

/// The SF Symbols offered by the builder's glyph picker. Any symbol name round-trips through
/// the model; this is just the curated set a lifter can choose from.
enum RoutineSymbol {
    static let options: [String] = [
        "dumbbell", "figure.strengthtraining.traditional", "figure.strengthtraining.functional",
        "figure.core.training", "figure.run", "figure.highintensity.intervaltraining",
        "figure.arms.open", "flame", "bolt", "heart", "star", "sun.max", "moon", "leaf",
        "mountain.2", "trophy", "target", "arrow.up.right", "calendar", "1.circle", "2.circle",
        "3.circle", "a.circle", "b.circle", "c.circle"
    ]
}

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

/// A routine's symbol in a tinted rounded square — the same drawing on routine cards, Home's
/// scheduled card, widgets and the Live Activity.
struct RoutineGlyph: View {
    var symbolName: String
    var tint: String
    var size: CGFloat = 36

    var body: some View {
        let color = RoutineTint.named(tint).color
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// "GLYPH" card: the symbol and tint that mark this routine on cards, widgets and the
/// Live Activity. A row of tint dots and a wrapping grid of symbols; the pick previews live.
struct GlyphCard: View {
    @Binding var symbolName: String
    @Binding var tint: String

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: DGSpace.s2)]

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s3) {
                RoutineGlyph(symbolName: symbolName, tint: tint, size: 44)
                Text("Glyph").dgLabel()
                Spacer()
                tintRow
            }
            LazyVGrid(columns: columns, spacing: DGSpace.s2) {
                ForEach(RoutineSymbol.options, id: \.self) { symbol in
                    symbolButton(symbol)
                }
            }
        }
        .dgCard()
    }

    private var tintRow: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(RoutineTint.allCases) { option in
                Button { tint = option.rawValue } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(DGColor.ink1, lineWidth: tint == option.rawValue ? 2 : 0)
                        }
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(tint == option.rawValue ? .isSelected : [])
            }
        }
    }

    private func symbolButton(_ symbol: String) -> some View {
        let selected = symbol == symbolName
        return Button { symbolName = symbol } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? RoutineTint.named(tint).color : DGColor.ink3)
                .frame(width: 40, height: 40)
                .background(
                    selected ? RoutineTint.named(tint).color.opacity(0.16) : DGColor.surface2,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
