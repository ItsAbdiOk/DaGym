import Foundation
import GymCore
import Testing

@testable import DaGym

/// The "everything that shows a number is a door" rules: where each tap lands, decided in
/// pure functions so a wrong destination is caught here rather than by a confused friend.
@MainActor
@Suite("Screen doors")
struct ScreenDoorTests {
    private func card(_ rule: CoachRule, action: CoachSuggestedAction = .none) -> CoachCard {
        CoachCard(
            rule: rule, severity: .notice, title: "t", body: "b", evidence: [], suggestedAction: action,
            firedDate: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("an Insights card about one exercise opens that exercise")
    func cardWithExercise() {
        let id = UUID()
        let stalled = card(
            .stalledLift, action: .deloadExercise(exerciseName: "Bench", exerciseID: id, toWeightKg: 80)
        )
        #expect(CoachCardDoor.destination(for: stalled) == .exercise(id))
        let review = card(
            .trainingReview, action: .changeRepRange(exerciseID: id, exerciseName: "Squat", low: 5, high: 8)
        )
        #expect(CoachCardDoor.destination(for: review) == .exercise(id))
    }

    @Test("a card without an exercise id opens the screen that proves the rule")
    func cardByRule() {
        func door(_ rule: CoachRule, _ action: CoachSuggestedAction = .none) -> ScreenDestination {
            CoachCardDoor.destination(for: card(rule, action: action))
        }
        #expect(door(.stalledLift) == .exerciseCharts)
        #expect(door(.deloadOverdue, .planDeloadWeek) == .thisWeek(.trends))
        #expect(door(.muscleCoverageGap) == .muscleMap(.balance))
        #expect(door(.recoveryDebt, .restMuscle(.quads)) == .muscleDetail(.quads))
        #expect(door(.prMilestone) == .thisWeek(.records))
        #expect(door(.adherenceDrop) == .thisWeek(.consistency))
        #expect(door(.returnFromLayoff, .easeBackIn(loadFraction: 0.8)) == .thisWeek(.consistency))
    }

    @Test("the Progress hub's muscle tiles open that muscle, or the map when there is none")
    func muscleTiles() {
        let tile = ProgressHubSummary.MuscleTile(muscle: .chest, detail: "18 sets")
        #expect(ProgressHubView.muscleDoor(tile) == .muscleDetail(.chest))
        #expect(ProgressHubView.muscleDoor(nil) == .muscleMap(.balance))
    }

    @Test("the coverage callout names the muscle it is about")
    func calloutMuscle() {
        let gap = ProgressHubSummary.CoverageGap(muscle: .biceps, sets: 2)
        #expect(ProgressHubSummary.callout(gap).muscle == .biceps)
    }

    @Test("a coach bubble's menu lists each named exercise once")
    func menuExercises() {
        let bench = UUID()
        let squat = UUID()
        let targets: [CoachChatSaveTarget] = [
            .exerciseNote(exerciseID: bench, exerciseName: "Bench", note: "a"),
            .remember(gist: "x"),
            .exerciseNote(exerciseID: bench, exerciseName: "Bench", note: "b"),
            .exerciseNote(exerciseID: squat, exerciseName: "Squat", note: "c")
        ]
        let exercises = CoachChatSaveMenu.exercises(in: targets)
        #expect(exercises.map(\.id) == [bench, squat])
        #expect(exercises.map(\.name) == ["Bench", "Squat"])
    }

    @Test("every destination has the title its screen shows")
    func titles() {
        #expect(ScreenDestination.thisWeek(.records).title == "This week")
        #expect(ScreenDestination.muscleDetail(.chest).title == "Muscle map")
        #expect(ScreenDestination.equipmentProfiles.title == "Equipment profiles")
        #expect(TrendsDoor.sets.anchor == "thisWeek.card.sets")
    }

    @Test("a manual bodyweight reading can be corrected or removed; a Health one cannot")
    func editReading() throws {
        let store = try makeStore()
        let manual = store.logBodyweight(kg: 82, source: "manual")
        let health = store.logBodyweight(kg: 81, source: "health")
        #expect(store.updateBodyMeasurement(id: manual.id, kg: 82.5))
        #expect(!store.updateBodyMeasurement(id: health.id, kg: 70))
        #expect(store.recentBodyMeasurements().first { $0.id == manual.id }?.kg == 82.5)
        #expect(store.deleteBodyMeasurement(id: manual.id))
        #expect(!store.deleteBodyMeasurement(id: health.id))
        #expect(store.recentBodyMeasurements().map(\.id) == [health.id])
    }

    @Test("the workout stat tiles explain every number they show")
    func statExplanations() {
        for kicker in ["Volume", "Sets", "PRs", "Time"] {
            #expect(WorkoutStatTile.explanation(kicker: kicker) != kicker)
        }
    }
}
