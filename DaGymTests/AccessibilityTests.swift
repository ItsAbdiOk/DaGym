import Foundation
import GymCore
import Testing

@testable import DaGym

/// The VoiceOver strings added in the accessibility pass. Every one is computed by a pure
/// helper next to the view that shows it, so these are plain input/output checks — no
/// SwiftUI rendering, no simulator.
@MainActor
@Suite("Accessibility pass labels")
struct AccessibilityTests {
    // MARK: Set rows

    @Test("the on-deck set says so, after its done state")
    func currentSetSuffix() {
        let label = SetRowAccessibility.label(
            kind: .working, weight: "82.5", reps: "8", unit: "kg", done: false, isCurrent: true
        )
        #expect(label == "Set, 82.5 kg by 8 reps, not done, current set")
    }

    @Test("a set that is not on deck has no suffix")
    func notCurrentSet() {
        let label = SetRowAccessibility.label(kind: .working, weight: "80", reps: "5", unit: "kg", done: true)
        #expect(label == "Set, 80 kg by 5 reps, done")
    }

    @Test("cardio row reads kind, summary, state and on-deck flag")
    func cardioLabel() {
        let label = SetRowAccessibility.cardioLabel(
            kind: .working, summary: "25:30 · 5 km", done: false, isCurrent: true
        )
        #expect(label == "Set, 25:30 · 5 km, not done, current set")
        let warmup = SetRowAccessibility.cardioLabel(
            kind: .warmup, summary: "10:00", done: true, isCurrent: false
        )
        #expect(warmup == "Warm-up set, 10:00, done")
    }

    @Test("previous ghost reads as 'Previous' with a unit, or says there is none")
    func previousGhost() {
        let previous = SetRowAccessibility.previousLabel(weight: "80", reps: 8, unit: "kg")
        #expect(previous == "Previous, 80 kg by 8")
        #expect(SetRowAccessibility.previousLabel(weight: nil, reps: nil, unit: "kg") == "No previous set")
    }

    @Test("set-kind badge is never a bare number or letter")
    func setKindBadge() {
        #expect(SetKindBadge.accessibilityLabel(kind: .working, index: 2) == "Set 2")
        #expect(SetKindBadge.accessibilityLabel(kind: .warmup, index: 0) == "Warm-up set")
        #expect(SetKindBadge.accessibilityLabel(kind: .drop, index: 0) == SetKind.drop.displayName)
    }

    @Test("timed-hold done check names the hold and how to undo it")
    func timedHoldDone() {
        let logged = SetEntry(weightKg: 0, reps: 0, isDone: true, durationSeconds: 45)
        #expect(TimedSetRow.doneLabel(set: logged) == "Hold done, 0:45, tap to undo")
    }

    // MARK: Body map

    @Test("each lit muscle reads its own step word, matching the colour rounding")
    func bodyMapRegionLabels() {
        let chest = BodyMapAccessibility.regionLabel(muscle: .chest, value: 1, mode: .hit)
        #expect(chest == "Chest, worked hard")
        #expect(BodyMapAccessibility.stepWord(value: 0.5, mode: .hit) == "worked moderately")
        #expect(BodyMapAccessibility.stepWord(value: 0.2, mode: .hit) == "worked lightly")
        #expect(BodyMapAccessibility.stepWord(value: 1, mode: .recovery) == "spent")
        #expect(BodyMapAccessibility.stepWord(value: 0.75, mode: .recovery) == "mostly spent")
        #expect(BodyMapAccessibility.stepWord(value: 0.5, mode: .recovery) == "recovering")
        #expect(BodyMapAccessibility.stepWord(value: 0.1, mode: .recovery) == "fresh")
    }

    // MARK: Charts

    @Test("trend summary covers count, span, first, latest, low and high")
    func trendSummary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let dates = [3, 10, 17].map {
            calendar.date(from: DateComponents(year: 2026, month: 1, day: $0)) ?? .now
        }
        let summary = ChartAccessibility.trendSummary(
            title: "Bodyweight", dates: dates, values: [80, 78.5, 81],
            format: ChartAccessibility.formatter(unit: "kg"), calendar: calendar
        )
        #expect(summary == "Bodyweight, 3 readings from 3 Jan to 17 Jan, first 80 kg, latest 81 kg, "
            + "lowest 78.5 kg, highest 81 kg")
    }

    @Test("trend summary handles one reading and none")
    func trendSummaryEdges() {
        let none = ChartAccessibility.trendSummary(
            title: "Body fat", dates: [], values: [], format: { "\($0)" }
        )
        #expect(none == "Body fat, no readings")
        let one = ChartAccessibility.trendSummary(
            title: "Body fat", dates: [.now], values: [18],
            format: ChartAccessibility.formatter(unit: "percent")
        )
        #expect(one.hasPrefix("Body fat, one reading on "))
        #expect(one.hasSuffix(", 18 percent"))
    }

    @Test("weekly bar summary says the latest week and its direction")
    func periodSummary() {
        let summary = ChartAccessibility.periodSummary(
            title: "Weekly volume", periodNoun: "weeks", values: [3900, 4280, 5100, 4000],
            format: { "\(Int($0)) kg" }
        )
        #expect(summary
            == "Weekly volume, 4 weeks, 4000 kg this week, down from 5100 kg last week, best 5100 kg")
    }

    @Test("formatter keeps one decimal at most and drops an empty unit")
    func formatter() {
        #expect(ChartAccessibility.formatter(unit: "kg")(78.26) == "78.3 kg")
        #expect(ChartAccessibility.formatter(unit: "")(80) == "80")
    }

    // MARK: Stat tiles and deltas

    @Test("delta stat spells out the direction the colour shows")
    func deltaStat() {
        #expect(DeltaStat.accessibilityLabel(value: "4 280", label: "Volume", delta: "+12%")
            == "Volume, 4 280, up 12 percent on last week")
        #expect(DeltaStat.accessibilityLabel(value: "18", label: "Sets", delta: "-3")
            == "Sets, 18, down 3 on last week")
        #expect(DeltaStat.accessibilityLabel(value: "2", label: "Workouts", delta: nil) == "Workouts, 2")
    }

    @Test("weekly recap metric reads value, unit and delta as one sentence")
    func recapMetric() {
        #expect(WeeklyRecapCard.metricLabel(value: "12", unit: "sets", delta: ("+3", true))
            == "12 sets, up 3 on last week")
        #expect(WeeklyRecapCard.metricLabel(value: "1", unit: "personal records", delta: nil)
            == "1 personal records")
    }

    // MARK: Coach, onboarding

    @Test("coach severity is a word, not a dot colour")
    func coachSeverity() {
        #expect(CoachCardView.severityWord(.warning) == "Warning")
        #expect(CoachCardView.severityWord(.notice) == "Notice")
        #expect(CoachCardView.severityWord(.info) == "Information")
    }

    @Test("onboarding dots read as step N of M")
    func onboardingProgress() {
        #expect(OnboardingFlow.progressLabel(step: .units) == "Step 1 of 7")
        #expect(OnboardingFlow.progressLabel(step: .notifications) == "Step 7 of 7")
    }
}
