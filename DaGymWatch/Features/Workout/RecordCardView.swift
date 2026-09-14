import GymCore
import SwiftUI

/// Screen 5: the yellow record card. Short and haptic-led — dismisses itself after 1.6 s, any
/// tap skips it, and it never blocks the rest timer ticking behind it. Takes VoiceOver focus,
/// announces once, then hands focus back.
struct RecordCardView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    var card: WatchRecordCard
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        let unit = preferences.weightUnit
        VStack(spacing: 2) {
            Text("Personal record")
                .font(WatchFont.secondary)
                .foregroundStyle(Color.black.opacity(0.7))
            Text("Heaviest \(card.exerciseName.lowercased())")
                .font(WatchFont.bodyMedium)
                .foregroundStyle(.black)
                .lineLimit(1)
            Text(unit.format(kg: card.weightKg))
                .font(WatchFont.value(44, weight: .bold))
                .foregroundStyle(.black)
            Text("\(unit.symbol) × \(card.reps)")
                .font(WatchFont.body)
                .foregroundStyle(.black)
            Text(e1rmLine(unit: unit))
                .font(WatchFont.secondary)
                .foregroundStyle(Color.black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchColor.record)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { store.recordCard = nil }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($focused)
        .task {
            focused = true
            guard !store.holdsRecordCard else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            if store.recordCard?.id == card.id { store.recordCard = nil }
        }
    }

    private func e1rmLine(unit: WeightUnit) -> String {
        let new = "\(unit.format(kg: card.newE1RM)) \(unit.symbol)"
        guard let previous = card.previousE1RM else { return "e1RM \(new)" }
        return "e1RM \(unit.format(kg: previous)) → \(new)"
    }
}
