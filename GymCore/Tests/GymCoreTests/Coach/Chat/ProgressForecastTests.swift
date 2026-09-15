import Foundation
import Testing

@testable import GymCore

@Suite("ProgressForecast: weighted trend to a target e1RM")
struct ProgressForecastTests {
    private let now = CoachTestSupport.date("2026-09-14T10:00:00Z")
    private var calendar: Calendar { CoachTestSupport.calendar }

    /// One session a week for `weeks` weeks ending today, e1RM rising `slope` kg a week from `start`.
    private func series(weeks: Int, start: Double, slope: Double) -> [(date: Date, e1rmKg: Double)] {
        (0..<weeks).map { index in
            let age = weeks - 1 - index
            return (date: CoachTestSupport.daysAgo(age * 7, from: now), e1rmKg: start + slope * Double(index))
        }
    }

    @Test("a known slope gives a known date")
    func knownSlope() throws {
        let points = series(weeks: 8, start: 80, slope: 1)
        let forecast = try #require(
            ProgressForecast.forecast(points: points, targetKg: 92, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .ok)
        #expect(forecast.sessions == 8)
        #expect(forecast.currentE1RM == 87)
        #expect(abs(forecast.slopeKgPerWeek - 1) < 0.001)
        #expect(forecast.r2 > 0.999)
        let weeks = try #require(forecast.weeksToTarget)
        #expect(abs(weeks - 5) < 0.001)
        #expect(forecast.reachDate == CoachTestSupport.daysFromNow(35, from: now))
    }

    @Test("fewer than four sessions is no trend")
    func tooFewSessions() throws {
        let points = series(weeks: 3, start: 80, slope: 2)
        let forecast = try #require(
            ProgressForecast.forecast(points: points, targetKg: 100, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .tooFewSessions)
        #expect(forecast.sessions == 3)
        #expect(forecast.reachDate == nil)
        #expect(forecast.weeksToTarget == nil)
        #expect(forecast.slopeKgPerWeek == 0)
        #expect(forecast.currentE1RM == 84)
    }

    @Test("a plateau never reaches the target")
    func plateau() throws {
        let points = series(weeks: 10, start: 100, slope: 0)
        let forecast = try #require(
            ProgressForecast.forecast(points: points, targetKg: 110, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .flatOrNegative)
        #expect(forecast.reachDate == nil)
        #expect(abs(forecast.slopeKgPerWeek) < 0.001)
    }

    @Test("a falling line never reaches the target")
    func falling() throws {
        let points = series(weeks: 6, start: 100, slope: -1)
        let forecast = try #require(
            ProgressForecast.forecast(points: points, targetKg: 110, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .flatOrNegative)
        #expect(forecast.slopeKgPerWeek < 0)
    }

    @Test("a target already lifted needs no line")
    func alreadyThere() throws {
        let points = series(weeks: 6, start: 90, slope: 2)
        let forecast = try #require(
            ProgressForecast.forecast(points: points, targetKg: 95, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .alreadyThere)
        #expect(forecast.currentE1RM == 100)
        #expect(forecast.reachDate == nil)
    }

    @Test("points outside the window are ignored; an empty window is nil")
    func window() {
        let old = (0..<6).map { index in
            (date: CoachTestSupport.daysAgo(100 + index * 7, from: now), e1rmKg: 80.0 + Double(index))
        }
        #expect(ProgressForecast.forecast(points: old, targetKg: 100, now: now, calendar: calendar) == nil)
        let future = [(date: CoachTestSupport.daysFromNow(1, from: now), e1rmKg: 120.0)]
        #expect(ProgressForecast.forecast(points: future, targetKg: 100, now: now, calendar: calendar) == nil)
        let mixed = old + series(weeks: 2, start: 90, slope: 1)
        let forecast = ProgressForecast.forecast(points: mixed, targetKg: 100, now: now, calendar: calendar)
        #expect(forecast?.sessions == 2)
        #expect(forecast?.caveat == .tooFewSessions)
    }

    @Test("recent sessions outweigh old ones")
    func recencyWeighting() throws {
        // Six flat weeks then six weeks climbing 2 kg/week: an unweighted fit would read the
        // average of both; the weighted one leans toward the climb.
        let flat = (0..<6).map { index in
            (date: CoachTestSupport.daysAgo((11 - index) * 7, from: now), e1rmKg: 100.0)
        }
        let climb = series(weeks: 6, start: 100, slope: 2)
        let forecast = try #require(
            ProgressForecast.forecast(points: flat + climb, targetKg: 130, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .ok)
        let unweighted = ProgressForecast.weightedFit(
            (flat + climb).map { (x: -now.timeIntervalSince($0.date) / (7 * 86_400), y: $0.e1rmKg, w: 1.0) }
        )
        #expect(forecast.slopeKgPerWeek > unweighted.slope + 0.2)
        #expect(forecast.slopeKgPerWeek < 2)
    }

    @Test("the fitted line is used for the horizon, not the last session alone")
    func lineAboveLatest() throws {
        // A rising line with one low final session: the target is "any day now", not in the past.
        var points = series(weeks: 8, start: 80, slope: 2)
        points[points.count - 1].e1rmKg = 88
        let forecast = try #require(
            ProgressForecast.forecast(points: points, targetKg: 92, now: now, calendar: calendar)
        )
        #expect(forecast.caveat == .ok)
        let weeks = try #require(forecast.weeksToTarget)
        #expect(weeks >= 0)
        #expect(weeks < 2)
    }

    @Test("a degenerate fit is slope zero")
    func degenerateFit() {
        let fit = ProgressForecast.weightedFit([(x: 0, y: 100, w: 1), (x: 0, y: 102, w: 1)])
        #expect(fit.slope == 0)
        #expect(fit.intercept == 101)
        #expect(ProgressForecast.weightedFit([]).slope == 0)
    }

    @Test("the forecast round-trips as JSON for the tool result")
    func codable() throws {
        let forecast = ProgressForecast.Forecast(
            reachDate: now, weeksToTarget: 3.5, slopeKgPerWeek: 1.25, r2: 0.9, sessions: 7,
            currentE1RM: 95.5, caveat: .ok
        )
        let data = try JSONEncoder().encode(forecast)
        #expect(try JSONDecoder().decode(ProgressForecast.Forecast.self, from: data) == forecast)
    }
}
