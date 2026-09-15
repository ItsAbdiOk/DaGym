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
    /// Neither model could answer — shown in the card's place so a tap never ends in nothing.
    @State private var failed = false
    /// The in-flight generation, cancelled when the section leaves the screen so a slow model
    /// never writes an answer into a view that is gone.
    @State private var askTask: Task<Void, Never>?

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
                    .onSubmit { askTask = Task { await ask() } }
                    .accessibilityIdentifier(A11yID.coachQuestion)
                Button { askTask = Task { await ask() } } label: {
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
            } else if failed {
                Text(CoachAskFallback.unanswered)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .dgCard(padding: DGSpace.s4)
                    .accessibilityIdentifier(A11yID.coachAnswer)
            }
        }
        .onDisappear { askTask?.cancel() }
    }

    @ViewBuilder
    private func answerCard(_ answer: CoachAnswer) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            if answer.isGrounded {
                Text(answer.text)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            } else if answer.toolResults.isEmpty {
                // Ungrounded and nothing from the tools to show instead: say so rather than
                // rendering a header over an empty card.
                Text(CoachAskFallback.unanswered)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink2)
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
        let fromModel: CoachAnswer?
        do {
            fromModel = try await coach.model.answer(question: text, tools: source)
        } catch {
            coachLogger.error("Coach answer failed, falling back to rules: \(error, privacy: .public)")
            fromModel = nil
        }
        // A cancelled generation (the tab was left) must not repaint a view that is gone.
        guard !Task.isCancelled else { return }
        if let fromModel {
            answer = fromModel
        } else {
            // The rule model throws for any question it can't parse — that is the expected
            // "couldn't answer" path, not a failure worth logging.
            let fromRules = try? await RuleCoachModel().answer(question: text, tools: source)
            guard !Task.isCancelled else { return }
            answer = fromRules
        }
        failed = answer == nil
    }
}

/// The one line both the Coach tab and `AskDaGymIntent` fall back to when there is nothing
/// grounded to say — a question neither model could parse, or an ungrounded sentence with no
/// tool results behind it. Never an empty card, never an empty Siri reply.
enum CoachAskFallback {
    static let unanswered = "I couldn't answer that from your log."

    /// The text to show or speak for `answer`: its sentence when grounded, the tool results
    /// when it isn't, and `unanswered` when there are none.
    static func spokenText(for answer: CoachAnswer?) -> String {
        guard let answer else { return unanswered }
        if answer.isGrounded { return answer.text }
        let fromTools = answer.toolResults.map(\.text).joined(separator: " ")
        return fromTools.isEmpty ? unanswered : fromTools
    }
}
