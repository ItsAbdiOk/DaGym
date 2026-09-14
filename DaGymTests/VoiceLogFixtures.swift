import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Shared setup for the voice-logging suites. Split out so each suite stays under SwiftLint's
/// type-body-length cap while still building identical sessions, stores and controllers.
@MainActor
enum VoiceLogFixtures {
    static func exercise(_ name: String = "Bench Press", equipment: String = "Barbell") -> ExerciseInfo {
        ExerciseInfo(
            name: name, primary: [.chest], equipment: equipment, incrementKg: 2.5, bar: .olympic
        )
    }

    static func session(_ entries: [WorkoutExerciseEntry]) -> WorkoutSession {
        let session = WorkoutSession(
            title: "Push", subtitle: "", startedAt: Date(), exercises: entries
        )
        session.restHaptics = false
        return session
    }

    /// One barbell exercise with a single empty planned set — the shape most of these tests need.
    static func singleSetSession() -> WorkoutSession {
        session([WorkoutExerciseEntry(exercise: exercise(), sets: [SetEntry(weightKg: 0, reps: 0)])])
    }

    static func store() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    static func preferences(unit: WeightUnit = .kg, autoLog: Bool = false) -> Preferences {
        let suite = UserDefaults(suiteName: "VoiceLogFixtures-\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(suite: suite)
        preferences.weightUnit = unit
        preferences.voiceAutoLogEnabled = autoLog
        return preferences
    }

    static func controller(_ recognizer: FakeSpeechRecognizer) -> VoiceLogController {
        VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())
    }
}
