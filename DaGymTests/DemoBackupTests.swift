import Foundation
import GymCore
import SwiftData
import Testing
@testable import DaGym

/// Writes a demo backup — fourteen months of a plausible lifter — through the real store and
/// the real export, so it restores like any other backup. Skipped unless `DAGYM_DEMO_BACKUP_OUT`
/// names the file to write (`TEST_RUNNER_DAGYM_DEMO_BACKUP_OUT=… xcodebuild test
/// -only-testing:DaGymTests/DemoBackupTests`). Not a test of anything; a generator that lives
/// here because it needs the app's models.
@MainActor
@Suite("Demo backup", .serialized)
struct DemoBackupTests {

    @Test(
        "fourteen months of history exports to DAGYM_DEMO_BACKUP_OUT",
        .enabled(if: ProcessInfo.processInfo.environment["DAGYM_DEMO_BACKUP_OUT"] != nil)
    )
    func writeDemoBackup() throws {
        let path = try #require(ProcessInfo.processInfo.environment["DAGYM_DEMO_BACKUP_OUT"])
        let builder = try CoachEvalStoreBuilder()
        var story = DemoLifter(builder: builder)
        try story.build()
        builder.finish()

        let preferences = Preferences(suite: UserDefaults(suiteName: "demo-backup-\(UUID())") ?? .standard)
        preferences.weeklyGoal = 4
        preferences.trainingGoal = .strength
        let document = BackupService.export(context: builder.store.context, preferences: preferences)
        let data = try BackupCodec.encode(document)
        try data.write(to: URL(fileURLWithPath: path))
        #expect(document.workouts.count > 200, Comment(rawValue:
            "DEMO wrote \(data.count / 1024) KB: \(document.workouts.count) workouts, "
            + "\(document.routines.count) routines, \(document.bodyMeasurements.count) bodyweights"))
    }
}

/// Three phases: a beginner full-body year opener, an upper/lower block with deloads, and a
/// current strength block where the bench stalls — enough texture for charts, records,
/// consistency, recovery and the coach to all have something to say.
@MainActor
private struct DemoLifter {
    typealias Lift = CoachEvalLift
    typealias Entry = CoachEvalStoreBuilder.Entry

    let builder: CoachEvalStoreBuilder
    private var rng = SplitMix(seed: 0x5EED_2026)

    init(builder: CoachEvalStoreBuilder) { self.builder = builder }

    mutating func build() throws {
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        try phaseOne()
        try phaseTwo()
        try phaseThree()
        bodyweights()
        notes()
    }

    // MARK: - Phase 1 · weeks 60–41, three-day full body

    private mutating func phaseOne() throws {
        for weekAgo in stride(from: 60, through: 41, by: -1) {
            let progress = Double(60 - weekAgo)
            for (day, shift) in [1.0, 3.0, 5.0].enumerated() where !missed(chance: 0.08) {
                let heavy = day != 1
                try builder.session(
                    daysAgo: Double(weekAgo) * 7 + shift, title: "Full Body", minutes: 55 + jitter(10),
                    entries: [
                        entry(Lift.squat, 3, 40 + progress * 2.5, heavy ? 5 : 8, rpe: 7),
                        entry(Lift.bench, 3, 30 + progress * 1.25, heavy ? 5 : 8, rpe: 7),
                        entry(Lift.row, 3, 30 + progress * 1.25, 8, rpe: 7),
                        entry(Lift.press, 2, 20 + progress * 0.75, 8, rpe: 8),
                        entry(Lift.curl, 2, 15 + progress * 0.5, 10, rpe: 8)
                    ]
                )
            }
        }
    }

    // MARK: - Phase 2 · weeks 40–21, upper/lower with a deload every sixth week

    private mutating func phaseTwo() throws {
        for weekAgo in stride(from: 40, through: 21, by: -1) {
            let progress = Double(40 - weekAgo)
            let deload = (40 - weekAgo) % 6 == 5
            let scale = deload ? 0.85 : 1.0
            let sets = deload ? 2 : 4
            for (day, shift) in [1.0, 2.0, 4.0, 5.0].enumerated() where !missed(chance: 0.1) {
                let upper = day % 2 == 0
                try builder.session(
                    daysAgo: Double(weekAgo) * 7 + shift, title: upper ? "Upper" : "Lower",
                    minutes: (deload ? 45 : 65) + jitter(8),
                    entries: upper ? [
                        entry(Lift.bench, sets, (65 + progress * 1.25) * scale, 5, rpe: deload ? 6 : 8),
                        entry(Lift.row, sets, (60 + progress * 1.25) * scale, 6, rpe: 8),
                        entry(Lift.press, 3, (37.5 + progress * 0.5) * scale, 6, rpe: 8),
                        entry(Lift.pulldown, 3, (50 + progress) * scale, 10, rpe: 8),
                        entry(Lift.lateralRaise, 3, 8 + (progress / 8).rounded(), 15, rpe: 9),
                        entry(Lift.pushdown, 3, (20 + progress * 0.5) * scale, 12, rpe: 8)
                    ] : [
                        entry(Lift.squat, sets, (90 + progress * 2.5) * scale, 5, rpe: deload ? 6 : 8),
                        entry(Lift.rdl, 3, (80 + progress * 2) * scale, 8, rpe: 8),
                        entry(Lift.legPress, 3, (140 + progress * 5) * scale, 10, rpe: 8),
                        entry(Lift.legCurl, 3, (35 + progress * 0.5) * scale, 12, rpe: 8)
                    ]
                )
            }
        }
    }

    // MARK: - Phase 3 · weeks 20–0, strength block; bench stalls at 100 for the last month

    private mutating func phaseThree() throws {
        let titles = ["Squat day", "Bench day", "Deadlift day", "Press day"]
        for weekAgo in stride(from: 20, through: 0, by: -1) {
            let progress = Double(20 - weekAgo)
            let bench = min(100, 87.5 + (progress * 1.25 / 2.5).rounded(.down) * 2.5)
            let stalled = weekAgo < 4
            for (day, shift) in [1.0, 2.0, 4.0, 6.0].enumerated() where !missed(chance: 0.07) {
                try builder.session(
                    daysAgo: Double(weekAgo) * 7 + shift, title: titles[day], minutes: 70 + jitter(12),
                    entries: phaseThreeEntries(day: day, progress: progress, bench: bench, stalled: stalled)
                )
            }
        }
        var routines: [RoutineInfo] = []
        for (day, title) in titles.enumerated() {
            let entries = phaseThreeEntries(day: day, progress: 20, bench: 100, stalled: true)
            routines.append(try builder.routine(title, entries: entries))
        }
        builder.store.saveSchedule(WeeklySchedule(days: [
            .monday: routines[0].id, .tuesday: routines[1].id,
            .thursday: routines[2].id, .saturday: routines[3].id
        ]))
    }

    private mutating func phaseThreeEntries(
        day: Int, progress: Double, bench: Double, stalled: Bool
    ) -> [Entry] {
        switch day {
        case 0:
            return [
                entry(Lift.squat, 5, 140 + (progress * 2.5 / 2.5).rounded(.down) * 2.5, 3, rpe: 8),
                entry(Lift.legPress, 3, 220 + progress * 5, 8, rpe: 8),
                entry(Lift.legCurl, 3, 45 + (progress / 4).rounded() * 2.5, 12, rpe: 8)
            ]
        case 1:
            return [
                entry(Lift.bench, 5, bench, 5, rpe: stalled ? 9.5 : 8),
                entry(Lift.dbBench, 3, 32 + (progress / 5).rounded() * 2, 10, rpe: 8),
                entry(Lift.pushdown, 3, 30 + (progress / 4).rounded() * 2.5, 12, rpe: 8),
                entry(Lift.lateralRaise, 4, 10, 15, rpe: 9)
            ]
        case 2:
            return [
                entry(Lift.deadlift, 3, 160 + (progress * 2.5 / 2.5).rounded(.down) * 2.5, 3, rpe: 8.5),
                entry(Lift.row, 4, 80 + (progress / 2).rounded() * 2.5, 6, rpe: 8),
                entry(Lift.pulldown, 3, 65 + (progress / 4).rounded() * 2.5, 10, rpe: 8),
                entry(Lift.curl, 3, 30, 10, rpe: 8)
            ]
        default:
            return [
                entry(Lift.press, 5, 52.5 + (progress / 4).rounded() * 2.5, 5, rpe: 8),
                entry(Lift.dbPress, 3, 24 + (progress / 5).rounded() * 2, 10, rpe: 8),
                entry(Lift.dbRow, 3, 34 + (progress / 5).rounded() * 2, 10, rpe: 8),
                entry(Lift.bandPullApart, 3, 0, 20, rpe: 7)
            ]
        }
    }

    // MARK: - Body and notes

    private mutating func bodyweights() {
        // 88 → 82 over the first eight months (a cut), then a slow climb back to 84.
        for weekAgo in stride(from: 60, through: 0, by: -1) {
            let base = weekAgo > 25
                ? 88 - Double(60 - weekAgo) * (6.0 / 35)
                : 82 + Double(25 - weekAgo) * (2.0 / 25)
            let kg = (base + Double(jitter(6)) / 10).rounded(toNearest: 0.1)
            builder.bodyweight(kg: kg, daysAgo: Double(weekAgo) * 7 + 0.5)
        }
    }

    private func notes() {
        let store = builder.store
        let notes: [(String, String, ExerciseNoteScope)] = [
            (Lift.squat, "Belt on for anything over 140. Knees out on the way down.", .always),
            (Lift.bench, "Pause the first rep of every set — it's where the stall is.", .next),
            (Lift.deadlift, "Hook grip from 160 up; straps for the back-off sets.", .always),
            (Lift.press, "Squeeze glutes before the press or the lower back arches.", .always)
        ]
        for (name, text, scope) in notes {
            guard let model = try? builder.exercise(name) else { continue }
            store.addExerciseNote(
                exerciseID: model.id, text: text, scope: scope,
                createdAt: builder.now.addingTimeInterval(-Double(scope == .next ? 3 : 90) * 86_400)
            )
        }
    }

    // MARK: - Texture

    private mutating func entry(
        _ name: String, _ count: Int, _ kg: Double, _ reps: Int, rpe: Double
    ) -> Entry {
        var entry = Entry(name, count: count, kg: kg.rounded(toNearest: 2.5), reps: reps, rpe: rpe)
        // The last set often loses a rep, and RPE drifts up with it.
        if count > 1, rng.next() % 3 == 0 {
            entry.sets[count - 1].reps = max(1, reps - 1)
            entry.sets[count - 1].rpe = min(10, rpe + 0.5)
        }
        return entry
    }

    private mutating func missed(chance: Double) -> Bool {
        Double(rng.next() % 1000) / 1000 < chance
    }

    private mutating func jitter(_ span: Int) -> Int {
        Int(rng.next() % UInt64(span * 2 + 1)) - span
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double { (self / step).rounded() * step }
}

/// Tiny deterministic generator so the demo file is the same every run.
private struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
