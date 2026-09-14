import Foundation
import Testing
@testable import GymCore

@Suite("Milestones")
struct MilestonesTests {
    private func state(
        workoutCount: Int = 0, streakWeeks: Int = 0, lifetimeTonnageKg: Double = 0,
        consistentWeeks: Int = 0, bodyweightKg: Double? = nil, bestE1RM: [String: Double] = [:]
    ) -> MilestoneState {
        MilestoneState(
            workoutCount: workoutCount, streakWeeks: streakWeeks, lifetimeTonnageKg: lifetimeTonnageKg,
            consistentWeeks: consistentWeeks, bodyweightKg: bodyweightKg, bestE1RM: bestE1RM
        )
    }

    @Test("workout count crosses bronze threshold")
    func workoutCountBronze() {
        let result = Milestones.evaluate(state: state(workoutCount: 10), earned: [])
        let match = result.first { $0.id == "workoutCount" }
        #expect(match?.tier == .bronze)
    }

    @Test("below every threshold earns nothing")
    func belowThreshold() {
        let result = Milestones.evaluate(state: state(workoutCount: 9), earned: [])
        #expect(!result.contains { $0.id == "workoutCount" })
    }

    @Test("already-earned tier is not re-earned")
    func noReEarning() {
        let result = Milestones.evaluate(
            state: state(workoutCount: 10), earned: [(id: "workoutCount", tier: .bronze)]
        )
        #expect(!result.contains { $0.id == "workoutCount" })
    }

    @Test("crossing straight to gold also awards the bronze and silver tiers it passed")
    func higherTierUpgrade() {
        // Importing 200 workouts at once used to list Gold and leave Bronze and Silver
        // permanently unowned — a gap in the milestones list for tiers plainly earned.
        let result = Milestones.evaluate(state: state(workoutCount: 200), earned: [])
        let tiers = result.filter { $0.id == "workoutCount" }.map(\.tier)
        #expect(tiers == [.bronze, .silver, .gold])
    }

    @Test("crossing two tiers at once awards both, and never one already earned")
    func twoTiersAtOnceFromBronze() {
        let result = Milestones.evaluate(
            state: state(workoutCount: 200), earned: [(id: "workoutCount", tier: .bronze)]
        )
        #expect(result.filter { $0.id == "workoutCount" }.map(\.tier) == [.silver, .gold])
    }

    @Test("upgrading from bronze to silver reports silver only")
    func tierUpgradeFromExisting() {
        let result = Milestones.evaluate(
            state: state(workoutCount: 50), earned: [(id: "workoutCount", tier: .bronze)]
        )
        let match = result.first { $0.id == "workoutCount" }
        #expect(match?.tier == .silver)
    }

    @Test("strength milestones need a bodyweight reading")
    func strengthNeedsBodyweight() {
        let result = Milestones.evaluate(
            state: state(bestE1RM: ["bench": 100]), earned: []
        )
        #expect(!result.contains { $0.id == "strength.bench" })
    }

    @Test("strength ratio bronze at 0.75x bodyweight")
    func strengthRatioBronze() {
        let result = Milestones.evaluate(
            state: state(bodyweightKg: 80, bestE1RM: ["bench": 60]), earned: []
        )
        let match = result.first { $0.id == "strength.bench" }
        #expect(match?.tier == .bronze)
    }

    @Test("strength ratio just under bronze earns nothing")
    func strengthRatioBelowBronze() {
        let result = Milestones.evaluate(
            state: state(bodyweightKg: 80, bestE1RM: ["bench": 59]), earned: []
        )
        #expect(!result.contains { $0.id == "strength.bench" })
    }

    @Test("streak, tonnage and consistency thresholds")
    func otherMetrics() {
        let result = Milestones.evaluate(
            state: state(streakWeeks: 12, lifetimeTonnageKg: 500_000, consistentWeeks: 26), earned: []
        )
        #expect(result.filter { $0.id == "streakWeeks" }.map(\.tier) == [.bronze, .silver])
        #expect(result.filter { $0.id == "lifetimeTonnage" }.map(\.tier) == [.bronze, .silver])
        #expect(result.filter { $0.id == "consistencyWeeks" }.map(\.tier) == [.bronze, .silver])
    }

    @Test("celebration worthy for a workout finished moments ago")
    func celebrationWorthyNow() {
        let now = Date()
        #expect(Milestones.isCelebrationWorthy(workoutDate: now.addingTimeInterval(-60), now: now))
    }

    @Test("not celebration worthy for a backfilled/past workout")
    func celebrationNotWorthyForPastDate() {
        let now = Date()
        let farPast = now.addingTimeInterval(-60 * 60 * 24 * 3)
        #expect(!Milestones.isCelebrationWorthy(workoutDate: farPast, now: now))
    }

    @Test("progress fraction halfway between bronze and silver")
    func progressHalfway() {
        let result = Milestones.progress(state: state(workoutCount: 30))
        let match = result.first { $0.id == "workoutCount" }
        #expect(match?.currentTier == .bronze)
        #expect(match?.nextThreshold == 50)
        #expect(abs((match?.progress ?? 0) - 0.5) < 0.001)
    }

    @Test("progress is 1.0 once gold is reached")
    func progressMaxed() {
        let result = Milestones.progress(state: state(workoutCount: 500))
        let match = result.first { $0.id == "workoutCount" }
        #expect(match?.currentTier == .gold)
        #expect(match?.nextThreshold == nil)
        #expect(match?.progress == 1)
    }

    @Test("line renders strength and tonnage milestones in the caller's unit")
    func lineUnitAware() throws {
        let definition = try #require(Milestones.definitions.first { $0.id == "strength.bench" })
        let bodyweightState = state(bodyweightKg: 80, bestE1RM: ["bench": 60])
        let kgLine = Milestones.line(for: definition, tier: .bronze, state: bodyweightState, unit: .kg)
        let lbLine = Milestones.line(for: definition, tier: .bronze, state: bodyweightState, unit: .lb)
        #expect(kgLine.contains("kg"))
        #expect(lbLine.contains("lb"))
        #expect(!lbLine.contains("kg"))
    }

    @Test("evaluate threads the unit through to the achievement line")
    func evaluateUnitAware() {
        let result = Milestones.evaluate(
            state: state(lifetimeTonnageKg: 500_000), earned: [], unit: .lb
        )
        let match = result.first { $0.id == "lifetimeTonnage" }
        #expect(match?.line.contains("lb") == true)
        #expect(match?.line.contains("kg") == false)
    }

    @Test("progress is 0 when a strength milestone has no bodyweight")
    func progressZeroWithoutBodyweight() {
        let result = Milestones.progress(state: state(bestE1RM: ["bench": 60]))
        let match = result.first { $0.id == "strength.bench" }
        #expect(match?.currentTier == nil)
        #expect(match?.progress == 0)
    }
}
