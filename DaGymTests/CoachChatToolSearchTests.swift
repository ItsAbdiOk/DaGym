import Foundation
import GymCore
import Testing

@testable import DaGym

/// The exercise search tool: what the gym allows, filters, and the one-call-per-muscle browse.
@MainActor
@Suite("Coach chat tool executor — search")
struct CoachChatToolSearchTests {
    @Test("search_exercises marks what the gym allows and why not")
    func search() async throws {
        let fixture = try CoachChatToolFixture.make()
        let search = try await fixture.call(.searchExercises, #"{"query":"press","allowed_only":false}"#)
        let exercises = try #require(search["exercises"] as? [[String: Any]])
        let bench = try #require(exercises.first { $0["name"] as? String == "Bench Press" })
        #expect(bench["allowed"] as? Bool == true)
        #expect(bench["reason"] == nil)
        let legPress = try #require(exercises.first { $0["name"] as? String == "Leg Press" })
        #expect(legPress["allowed"] as? Bool == false)
        #expect(legPress["reason"] as? String == "needs a Leg Press the gym does not have")
        #expect(legPress["machine"] as? String == "legPress")

        let machine = try await fixture.call(
            .searchExercises, #"{"query":"press","machine":"legPress","allowed_only":false}"#
        )
        #expect((machine["exercises"] as? [Any])?.count == 1)
        let dumbbell = try await fixture.call(.searchExercises, #"{"query":"row","equipment":"dumbbell"}"#)
        #expect((dumbbell["exercises"] as? [[String: Any]])?.first?["name"] as? String == "Dumbbell Row")

        // The default hides what the gym can't do, and a muscle alone is a valid filter — one call
        // per muscle group is how the model is told to browse, not one search per exercise.
        let allowed = try await fixture.call(.searchExercises, #"{"query":"press"}"#)
        let allowedNames = (allowed["exercises"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(allowedNames?.contains("Leg Press") == false)
        let chest = try await fixture.call(.searchExercises, #"{"muscle":"chest"}"#)
        let chestNames = (chest["exercises"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(chestNames?.contains("Bench Press") == true)
        await #expect(throws: CoachChatToolError.self) {
            _ = try await fixture.executor.execute(name: "search_exercises", argumentsJSON: "{}")
        }
    }
}
