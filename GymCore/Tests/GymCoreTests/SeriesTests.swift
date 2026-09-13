import Foundation
import Testing
@testable import GymCore

@Suite("Exercise series")
struct ExerciseSeriesTests {
    private func set(
        kind: SetKind = .working, weight: Double, reps: Int, date: Date = Date()
    ) -> PerformedSet {
        PerformedSet(kind: kind, weightKg: weight, reps: reps, date: date)
    }

    private let day1 = Date(timeIntervalSince1970: 0)
    private let day2 = Date(timeIntervalSince1970: 86400)

    @Test("e1rm excludes warm-ups and takes the best eligible set per session")
    func e1rmExcludesWarmups() {
        let sessions = [
            ExerciseSession(
                date: day1,
                sets: [
                    set(kind: .warmup, weight: 200, reps: 5),
                    set(weight: 100, reps: 5),
                    set(weight: 80, reps: 8)
                ]
            )
        ]
        let series = ExerciseSeries.e1rm(sessions: sessions)
        #expect(series.count == 1)
        let expected = OneRepMax.estimate(weight: 100, reps: 5)
        #expect(series[0].value == expected)
    }

    @Test("13-rep sets are excluded from e1RM but count toward volume")
    func thirteenRepsExcludedFromE1RMOnly() {
        let sessions = [ExerciseSession(date: day1, sets: [set(weight: 60, reps: 13)])]
        #expect(ExerciseSeries.e1rm(sessions: sessions).isEmpty)
        let volume = ExerciseSeries.volume(sessions: sessions)
        #expect(volume.count == 1)
        #expect(volume[0].value == 60 * 13)
    }

    @Test("topSet picks the heaviest weight, ties broken by more reps")
    func topSetPicksHeaviest() {
        let sessions = [
            ExerciseSession(
                date: day1,
                sets: [set(weight: 80, reps: 8), set(weight: 100, reps: 3), set(weight: 100, reps: 5)]
            )
        ]
        let series = ExerciseSeries.topSet(sessions: sessions)
        #expect(series.count == 1)
        #expect(series[0].value == 100)
    }

    @Test("volume sums weight times reps across completed, non-warm-up sets")
    func volumeSums() {
        let sessions = [
            ExerciseSession(
                date: day1,
                sets: [
                    set(kind: .warmup, weight: 40, reps: 10),
                    set(weight: 100, reps: 5), set(weight: 100, reps: 5)
                ]
            )
        ]
        #expect(ExerciseSeries.volume(sessions: sessions)[0].value == 1000)
    }

    @Test("volume includes a zero point for a session with no counting sets")
    func volumeIncludesZeroSession() {
        let sessions = [ExerciseSession(date: day1, sets: [set(kind: .warmup, weight: 40, reps: 10)])]
        let series = ExerciseSeries.volume(sessions: sessions)
        #expect(series.count == 1)
        #expect(series[0].value == 0)
    }

    @Test("repsAtWeight finds the best matching set per session, skipping sessions with none")
    func repsAtWeight() {
        let sessions = [
            ExerciseSession(date: day1, sets: [set(weight: 80, reps: 6), set(weight: 80, reps: 8)]),
            ExerciseSession(date: day2, sets: [set(weight: 90, reps: 5)])
        ]
        let series = ExerciseSeries.repsAtWeight(sessions: sessions, weight: 80)
        #expect(series.count == 1)
        #expect(series[0].value == 8)
    }

    @Test("mostCommonWeight returns the weight seen most across sessions")
    func mostCommonWeight() {
        let sessions = [
            ExerciseSession(date: day1, sets: [set(weight: 80, reps: 6), set(weight: 80, reps: 8)]),
            ExerciseSession(date: day2, sets: [set(weight: 90, reps: 5)])
        ]
        #expect(ExerciseSeries.mostCommonWeight(sessions: sessions) == 80)
    }

    @Test("empty inputs produce empty series")
    func empty() {
        #expect(ExerciseSeries.e1rm(sessions: []).isEmpty)
        #expect(ExerciseSeries.topSet(sessions: []).isEmpty)
        #expect(ExerciseSeries.volume(sessions: []).isEmpty)
        #expect(ExerciseSeries.repsAtWeight(sessions: [], weight: 80).isEmpty)
        #expect(ExerciseSeries.mostCommonWeight(sessions: []) == nil)
    }
}

@Suite("Body series")
struct BodySeriesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func set(weight: Double, reps: Int, date: Date = Date()) -> PerformedSet {
        PerformedSet(kind: .working, weightKg: weight, reps: reps, date: date)
    }

    @Test("weekly volume buckets by the calendar's first weekday")
    func weeklyVolumeHonoursFirstWeekday() {
        let now = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let midWeek = calendar.date(byAdding: .day, value: 2, to: weekStart) ?? weekStart
        let workouts = [
            BodyWorkout(
                date: weekStart, durationSeconds: 0,
                entries: [.init(primary: [.chest], secondary: [], sets: [set(weight: 100, reps: 5)])]
            ),
            BodyWorkout(
                date: midWeek, durationSeconds: 0,
                entries: [.init(primary: [.chest], secondary: [], sets: [set(weight: 100, reps: 5)])]
            )
        ]
        let series = BodySeries.weeklyVolume(workouts: workouts, calendar: calendar)
        #expect(series.count == 1)
        #expect(series[0].weekStart == weekStart)
        #expect(series[0].volumeKg == 1000)
    }

    @Test("sets per muscle counts primary at 1 and secondary at 0.5, within the day window")
    func setsPerMuscleWeighting() {
        let now = Date()
        let workouts = [
            BodyWorkout(
                date: now, durationSeconds: 0,
                entries: [
                    .init(
                        primary: [.chest], secondary: [.triceps],
                        sets: [set(weight: 80, reps: 8), set(weight: 80, reps: 8)]
                    )
                ]
            )
        ]
        let result = BodySeries.setsPerMuscle(workouts: workouts, days: 7, now: now, calendar: calendar)
        #expect(result[.chest] == 2)
        #expect(result[.triceps] == 1)
    }

    @Test("sets per muscle excludes workouts outside the day window")
    func setsPerMuscleExcludesOldWorkouts() {
        let now = Date()
        let old = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let workouts = [
            BodyWorkout(
                date: old, durationSeconds: 0,
                entries: [.init(primary: [.chest], secondary: [], sets: [set(weight: 80, reps: 8)])]
            )
        ]
        let result = BodySeries.setsPerMuscle(workouts: workouts, days: 7, now: now, calendar: calendar)
        #expect(result.isEmpty)
    }

    @Test("session durations are sorted oldest first")
    func sessionDurationsSorted() {
        let now = Date()
        let earlier = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let workouts = [
            BodyWorkout(date: now, durationSeconds: 3600, entries: []),
            BodyWorkout(date: earlier, durationSeconds: 1800, entries: [])
        ]
        let series = BodySeries.sessionDurations(workouts: workouts)
        #expect(series.map(\.date) == [earlier, now])
    }

    @Test("empty inputs produce empty series")
    func empty() {
        #expect(BodySeries.weeklyVolume(workouts: [], calendar: calendar).isEmpty)
        #expect(BodySeries.setsPerMuscle(workouts: [], days: 7, now: Date(), calendar: calendar).isEmpty)
        #expect(BodySeries.sessionDurations(workouts: []).isEmpty)
    }
}

@Suite("Balance windows")
struct BalanceWindowTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    private func workout(at date: Date, sets: [PerformedSet], muscle: Muscle = .chest) -> BodyWorkout {
        BodyWorkout(
            date: date, durationSeconds: 3600,
            entries: [BodyWorkout.MuscleEntry(primary: [muscle], secondary: [], sets: sets)]
        )
    }

    private func set(rpe: Double? = nil, kind: SetKind = .working, date: Date) -> PerformedSet {
        PerformedSet(kind: kind, weightKg: 60, reps: 8, date: date, rpe: rpe)
    }

    @Test("this week: Monday-start counts only Wednesday; Sunday-start counts Sunday too")
    func thisWeekHonoursWeekStart() {
        // 2024-01-07 is a Sunday, 2024-01-10 a Wednesday.
        let sunday = date("2024-01-07T10:00:00Z")
        let wednesday = date("2024-01-10T10:00:00Z")
        let now = date("2024-01-10T20:00:00Z")
        let workouts = [
            workout(at: sunday, sets: [set(date: sunday)]),
            workout(at: wednesday, sets: [set(date: wednesday)])
        ]
        let monday = calendar(firstWeekday: 2)
        let mondayTotals = BodySeries.setsPerMuscle(
            workouts: workouts, window: .thisWeek(monday), now: now, calendar: monday
        )
        #expect(mondayTotals[.chest] == 1)

        let sundayStart = calendar(firstWeekday: 1)
        let sundayTotals = BodySeries.setsPerMuscle(
            workouts: workouts, window: .thisWeek(sundayStart), now: now, calendar: sundayStart
        )
        #expect(sundayTotals[.chest] == 2)
    }

    @Test("hardOnly counts the RIR 0 set, not the four RIR 3 sets")
    func hardOnlyFilter() {
        let day = date("2024-01-10T10:00:00Z")
        let sets = (0..<4).map { _ in set(rpe: 7, date: day) } + [set(rpe: 10, date: day)]
        let workouts = [workout(at: day, sets: sets)]
        let calendar = calendar(firstWeekday: 2)
        let hard = BodySeries.setsPerMuscle(
            workouts: workouts, window: .days(7), now: day, calendar: calendar, hardOnly: true
        )
        #expect(hard[.chest] == 1)
        let all = BodySeries.setsPerMuscle(workouts: workouts, window: .days(7), now: day, calendar: calendar)
        #expect(all[.chest] == 5)
    }

    @Test("failure and AMRAP sets are hard even without a rating; warm-ups never are")
    func hardKinds() {
        let day = date("2024-01-10T10:00:00Z")
        let sets = [
            set(kind: .failure, date: day), set(kind: .amrap, date: day),
            set(rpe: 10, kind: .warmup, date: day), set(rpe: 8.5, date: day)
        ]
        let hard = BodySeries.setsPerMuscle(
            workouts: [workout(at: day, sets: sets)], window: .allTime, now: day,
            calendar: calendar(firstWeekday: 2), hardOnly: true
        )
        #expect(hard[.chest] == 2)
    }

    @Test("allTime over 400 workouts equals the sum of every counting set")
    func allTimeSumsEverything() {
        let calendar = calendar(firstWeekday: 2)
        let now = date("2024-01-10T10:00:00Z")
        let workouts = (0..<400).map { index -> BodyWorkout in
            let day = now.addingTimeInterval(-Double(index) * 86_400)
            let sets = (0..<(index % 5 + 1)).map { _ in set(date: day) } + [set(kind: .warmup, date: day)]
            return workout(at: day, sets: sets, muscle: index % 2 == 0 ? .chest : .lats)
        }
        let totals = BodySeries.setsPerMuscle(
            workouts: workouts, window: .allTime, now: now, calendar: calendar
        )
        let expectedChest = workouts.filter { $0.entries[0].primary == [.chest] }
            .flatMap(\.entries).flatMap(\.sets).filter { $0.kind.countsTowardStats }.count
        let expectedLats = workouts.filter { $0.entries[0].primary == [.lats] }
            .flatMap(\.entries).flatMap(\.sets).filter { $0.kind.countsTowardStats }.count
        #expect(totals[.chest] == Double(expectedChest))
        #expect(totals[.lats] == Double(expectedLats))
        let trailing = BodySeries.setsPerMuscle(
            workouts: workouts, window: .days(7), now: now, calendar: calendar
        )
        #expect((trailing[.chest] ?? 0) + (trailing[.lats] ?? 0) < Double(expectedChest + expectedLats))
    }
}
