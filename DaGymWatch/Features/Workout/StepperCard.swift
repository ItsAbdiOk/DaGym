import GymCore
import SwiftUI

/// Which stepper holds the crown. One at a time, marked by the coral inset border; with none
/// focused the crown scrolls the screen.
enum CrownField: Hashable {
    case weight, reps, effort, assistance, distance
}

/// A 64 pt stepper card (16 pt radius): the number, its unit label, and the crown-focus border.
/// `hollow` is the warm-up look — an outline instead of a fill says "doesn't count" while the
/// target stays the same size. `tall` is the 88 pt single-value card (bodyweight).
///
/// To VoiceOver it is an adjustable value — "Weight, 100 kilograms, adjustable" — and a swipe
/// up or down moves it one crown detent through `onAdjust`.
struct StepperCard: View {
    var value: String
    var label: String
    var field: CrownField
    var focus: CrownField?
    var hollow = false
    var tall = false
    /// Overrides the card height (the cardio distance card is a short one).
    var height: CGFloat?
    var valueSize: CGFloat = 28
    var accessibilityName: String
    var accessibilityValue: String
    var onTap: () -> Void
    var onAdjust: (AccessibilityAdjustmentDirection) -> Void = { _ in }

    private var isFocused: Bool { focus == field }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: tall ? 2 : 0) {
                Text(value)
                    .font(WatchFont.value(valueSize))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(WatchFont.unit)
                    .foregroundStyle(WatchColor.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height ?? (tall ? WatchMetric.singleValueCard : WatchMetric.stepperCard))
            .background(
                RoundedRectangle(cornerRadius: WatchMetric.stepperRadius)
                    .fill(hollow ? Color.clear : WatchColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WatchMetric.stepperRadius)
                    .strokeBorder(
                        isFocused ? WatchColor.accent : (hollow ? WatchColor.separator : .clear),
                        lineWidth: isFocused ? WatchMetric.crownFocusBorder : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: WatchMetric.stepperRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction(onAdjust)
        .accessibilityHint(isFocused ? "Turn the crown to adjust" : "Tap to give the crown")
    }
}

/// Binds the crown to whichever field is focused: one detent per exercise increment, a
/// selection click on each, and nothing when no card is focused (the crown scrolls then).
struct CrownBinding: ViewModifier {
    @Binding var crown: Double
    var focus: CrownField?
    var step: Double
    var range: ClosedRange<Double>

    func body(content: Content) -> some View {
        content
            .focusable(focus != nil)
            .digitalCrownRotation(
                $crown, from: range.lowerBound, through: range.upperBound, by: step,
                sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
            )
    }
}
