import GymCore
import SwiftUI

/// "Showing what's in **Home** · hiding 212 by equipment, 14 by machine · Show all" — the
/// equipment-profile filter's line, shared by the library and the exercise picker. A dim
/// sentence rather than a control strip (the redesign prototype), with the profile name bold and
/// the trailing accent word the tap that flips the filter.
struct EquipmentFilterBanner: View {
    var profileName: String
    var hidden = HiddenCounts()
    @Binding var showingAll: Bool

    /// "Showing what's in Home" plus how many rows the profile hides, split by the reason.
    static func title(profileName: String, hidden: HiddenCounts, showingAll: Bool) -> String {
        if showingAll { return "Showing all equipment" }
        return "Showing what's in \(profileName)\(hiddenSuffix(hidden))"
    }

    /// " · hiding 212 by equipment, 14 by machine", or nothing when the profile hides no row.
    static func hiddenSuffix(_ hidden: HiddenCounts) -> String {
        var parts: [String] = []
        if hidden.byType > 0 { parts.append("\(hidden.byType) by equipment") }
        if hidden.byMachine > 0 { parts.append("\(hidden.byMachine) by machine") }
        guard !parts.isEmpty else { return "" }
        return " · hiding \(parts.joined(separator: ", "))"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DGSpace.s1) {
            // The sentence names the profile doing the hiding, so it opens Equipment profiles.
            NavigationLink(value: ScreenDestination.equipmentProfiles) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    sentence
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DGColor.ink4)
                }
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dgRow)
            .accessibilityHint("Opens Equipment profiles")
            .accessibilityIdentifier(A11yID.libraryProfileBanner)
            Button(showingAll ? "Only \(profileName)" : "Show all") { showingAll.toggle() }
                .buttonStyle(.dgControl)
                .font(DGFont.footnote.weight(.semibold))
                .foregroundStyle(DGColor.coralText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s1)
    }

    /// The same words `title` returns, with the profile name in bold.
    private var sentence: Text {
        if showingAll { return Text("Showing all equipment") }
        let name = Text(profileName).fontWeight(.semibold)
        return Text("Showing what's in \(name)\(Self.hiddenSuffix(hidden))")
    }
}

/// One row of the library's white row group (the redesign prototype's `libRows`): a small
/// illustration, the name over its muscles, the best estimated 1RM on the right and a gold
/// star for a favourite. The hairline under it belongs to the row so the group needs no
/// `Divider` bookkeeping; the last row goes without.
struct LibraryRow: View {
    var exercise: ExerciseInfo
    var isLast = false

    @Environment(Preferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: exercise)
            // The 1RM figure sits beside the name, or under it at accessibility sizes — beside
            // a 50 pt name it left room for three letters ("Bar…").
            DGAdaptiveStack(spacing: DGSpace.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink1)
                        .lineLimit(Self.nameLineLimit(dynamicTypeSize))
                    Text(exercise.muscleLine)
                        .font(DGFont.caption.weight(.regular))
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: DGSpace.s2)
                accessory
            }
            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.prGold)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, DGSpace.s3)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(DGColor.hairline).frame(height: 0.5).padding(.leading, 15)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exercise.isFavorite ? "\(exercise.name), favourite" : exercise.name)
        .accessibilityValue(accessibilityValue)
    }

    /// One line normally; at accessibility sizes a 50 pt name gets a second before "Barbell Be…".
    static func nameLineLimit(_ size: DynamicTypeSize) -> Int {
        size.dgStacks ? 2 : 1
    }

    private var accessibilityValue: String {
        if let best = exercise.bestE1RM {
            let figure = "\(preferences.formatWeight(kg: best)) \(preferences.unitSymbol)"
            return "\(exercise.muscleLine), estimated 1RM \(figure)"
        }
        return exercise.muscleLine
    }

    @ViewBuilder
    private var accessory: some View {
        if let best = exercise.bestE1RM {
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(preferences.formatWeight(kg: best)) \(preferences.unitSymbol)")
                    .font(DGFont.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                Text("est. 1RM")
                    .font(Font.system(.caption2))
                    .foregroundStyle(DGColor.ink3)
            }
        } else if exercise.loggingStyle == .weightedBodyweight {
            DGTag(text: "BW+", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
        } else if exercise.isCustom {
            DGTag(text: "Mine", tint: DGColor.coralText, wash: DGColor.coralWash)
        }
    }
}
