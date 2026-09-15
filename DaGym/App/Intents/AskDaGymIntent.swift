import AppIntents
import Foundation
import GymCore

/// "Ask DaGym …" Siri Shortcut / App Intent: the same "ask about your training" the Coach tab
/// offers, answered without opening the app. Runs against the short-lived store
/// `LastSessionIntent` uses, through `CoachServices`' current model — the on-device model with
/// its five tools when it's available and on, the rule matcher otherwise. Either way the
/// numbers come from the store; a model answer the validator can't ground is replaced by the
/// tool results themselves.
struct AskDaGymIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About My Training"
    static let openAppWhenRun = false

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask DaGym \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentStoreAccess.makeStore() else {
            return .result(dialog: IntentDialog(stringLiteral: "DaGym isn't available right now."))
        }
        let preferences = Preferences()
        let services = CoachServices.make(preferences: preferences)
        let source = CoachFactsSource(
            store: store, unit: preferences.weightUnit, calendar: preferences.trainingCalendar
        )
        let answer = await Self.answer(question: question, model: services.model, source: source)
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }

    /// The spoken line: the model's sentence when it's grounded, the tool results when it isn't,
    /// and the rule matcher's answer when the model fails outright.
    static func answer(
        question: String, model: any CoachLanguageModel, source: any CoachToolAnswering
    ) async -> String {
        let answer: CoachAnswer?
        if let fromModel = try? await model.answer(question: question, tools: source) {
            answer = fromModel
        } else {
            answer = try? await RuleCoachModel().answer(question: question, tools: source)
        }
        guard let answer else { return "I couldn't look that up right now." }
        if answer.isGrounded { return answer.text }
        return answer.toolResults.map(\.text).joined(separator: " ")
    }
}
