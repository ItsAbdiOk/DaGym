import SwiftUI

/// The "…" beside Today's Start button: every other way into a session, as a medium sheet.
/// Rows only dismiss; `HomeView` runs the chosen action once the sheet is gone, because two of
/// them present something of their own (the backfill sheet, the coach chat cover).
struct StartSomethingElseSheet: View {
    /// The first few routines other than today's, for the "Pick another routine" subtitle.
    var routineNames: [String]
    var onFreestyle: () -> Void
    var onBackfill: () -> Void
    var onPickRoutine: () -> Void
    var onAskCoach: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Start something else")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .padding(.top, DGSpace.s6)
            VStack(spacing: 0) {
                row("Freestyle workout", "Empty session, add as you go", action: onFreestyle)
                    .accessibilityIdentifier(A11yID.homeFreestyle)
                row("Log a past workout", "Date, start time, duration", action: onBackfill)
                row("Pick another routine", routinesSubtitle, action: onPickRoutine)
                row("Ask the coach for a plan", "Goal, days, equipment", isLast: true, action: onAskCoach)
            }
            .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DGColor.hairline, lineWidth: 0.5)
            }
            .padding(.top, 14)
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(
                        DGColor.ink1.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(DGPressStyle())
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.bgBase)
    }

    private var routinesSubtitle: String {
        routineNames.isEmpty ? "Everything on the Train tab" : routineNames.joined(separator: " · ")
    }

    private func row(
        _ title: String, _ subtitle: String, isLast: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(DGColor.ink1)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HomeChevron()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(DGColor.hairline).frame(height: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DGPressStyle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StartSomethingElseSheet(
                routineNames: ["Pull", "Legs", "Upper light"],
                onFreestyle: {}, onBackfill: {}, onPickRoutine: {}, onAskCoach: {}
            )
        }
}
