import GymCore
import SwiftUI

/// "Ask about your training" on the Coach tab. The question goes to
/// `CoachLanguageModel.answer`, which reaches the store only through the five question tools
/// (`CoachFactsSource`) — the model never guesses a number. If the validator finds a number in
/// the answer that no tool returned, the tool results are shown instead of the sentence.
struct CoachAskSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(CoachServices.self) private var coach
    @State private var question = ""
    @State private var answer: CoachAnswer?
    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Ask").dgLabel()
            HStack(spacing: DGSpace.s2) {
                TextField("What did I bench last time?", text: $question)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                    .padding(.horizontal, DGSpace.s4)
                    .frame(minHeight: 44)
                    .dgCard(padding: 0)
                    .submitLabel(.send)
                    .onSubmit { Task { await ask() } }
                    .accessibilityIdentifier(A11yID.coachQuestion)
                Button { Task { await ask() } } label: {
                    Image(systemName: isAsking ? "ellipsis" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(DGColor.aiViolet, in: Circle())
                }
                .buttonStyle(.dgControl)
                .disabled(isAsking || question.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Ask")
            }
            if let answer {
                answerCard(answer)
            }
        }
    }

    @ViewBuilder
    private func answerCard(_ answer: CoachAnswer) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            if answer.isGrounded {
                Text(answer.text)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The sentence had a number no tool produced, so it isn't shown — the tool
                // results are, since those are the store's own numbers.
                Text("Here's what your log says:")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                ForEach(Array(answer.toolResults.enumerated()), id: \.offset) { _, result in
                    Text(result.text)
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dgCard(padding: DGSpace.s4)
        .accessibilityIdentifier(A11yID.coachAnswer)
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        let source = CoachFactsSource(
            store: store, unit: preferences.weightUnit,
            calendar: preferences.trainingCalendar
        )
        if let fromModel = try? await coach.model.answer(question: text, tools: source) {
            answer = fromModel
        } else {
            answer = try? await RuleCoachModel().answer(question: text, tools: source)
        }
    }
}
