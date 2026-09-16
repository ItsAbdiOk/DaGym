import Foundation
import GymCore
import SwiftUI

/// The one place the chat screen meets the store: builds a `CoachChatEngine` for a thread and
/// applies or undoes a draft. Every Store-slice name the chat depends on
/// (`StoreCoachChatToolExecutor`, `lifterProfileFacts`, `apply(_:)`/`undo(_:)`,
/// `coachModelID`, `coachReviewerModelID`, `coachChatConsentGiven`) is called from here and
/// nowhere else, so a signature change is a one-file fix.
@MainActor
enum CoachChatEngineFactory {
    /// A ready engine for `thread` (a fresh one when nil), persisting to the standard archive.
    /// The key is read from the Keychain per request, so one saved in Settings mid-chat is
    /// picked up without rebuilding.
    static func make(
        thread: CoachChatThread?, store: WorkoutStore, preferences: Preferences, now: Date = Date()
    ) -> CoachChatEngine {
        let client = OpenRouterClient(apiKey: CoachChatSettings.keyProvider)
        let calendar = preferences.trainingCalendar
        let memory = CoachMemoryFile.standard()
        let executor = StoreCoachChatToolExecutor(
            store: store, unit: preferences.weightUnit, weeklyGoal: preferences.weeklyGoal,
            calendar: calendar, memory: memory
        )
        let facts = store.lifterProfileFacts(
            unit: preferences.weightUnit, weeklyGoal: preferences.weeklyGoal, trainingGoal: nil, now: now,
            calendar: calendar
        )
        let prompt = CoachChatPrompt.system(
            profile: facts, memory: memory?.facts() ?? [], now: now, calendar: calendar
        )
        let engine = CoachChatEngine(
            client: client, executor: executor, configuration: configuration(preferences),
            systemPrompt: prompt, tools: (try? OpenRouterWire.toolDefinitions()) ?? [],
            thread: thread, archive: CoachChatArchive.standard(), ledger: .standard
        )
        executor.sourceThreadID = engine.threadID
        return engine
    }

    /// The chat preferences as the Services layer wants them: the drafter's model, consent,
    /// and the reviewer's model (nil when the second opinion is off).
    static func configuration(_ preferences: Preferences) -> CoachChatConfiguration {
        var configuration = CoachChatConfiguration(
            modelID: preferences.coachModelID, consentGiven: preferences.coachChatConsentGiven
        )
        configuration.reviewerModelID = preferences.coachReviewerModelID
        return configuration
    }

    /// Applies a draft; nil when the store refused it (its target routine is gone).
    static func apply(_ draft: CoachChatDraft, store: WorkoutStore) -> CoachChatApplication? {
        try? store.apply(draft)
    }

    static func undo(_ application: CoachChatApplication, store: WorkoutStore) {
        store.undo(application)
    }
}
