import Foundation

/// "When will I bench 100 kg?" — a weighted straight line through the last twelve weeks of
/// best-e1RM-per-session, extended forward to the target. Recent sessions count for more than
/// old ones (a half-life of `halfLifeWeeks`), so a lifter who changed programme a month ago is
/// read off the new programme, not the average of both. Pure: the caller passes `now` and the
/// calendar, so a test can pin the answer to the day.
///
/// The answer is a *forecast*, and the caveat says how much to trust it: fewer than
/// `minSessions` points is no trend at all, a flat or falling line never reaches the target,
/// and a target already lifted needs no line. The coach's prompt tells the model to repeat the
/// caveat, never to smooth it over.
public enum ProgressForecast {
    /// How far back the line looks. Anything older is a different lifter.
    public static let windowWeeks = 12
    /// A point this many weeks old weighs half as much as one from today, so the oldest point
    /// in the window still counts about an eighth — enough to steady the line, not to own it.
    public static let halfLifeWeeks = 4.0
    /// Fewer sessions than this in the window and no slope is fitted.
    public static let minSessions = 4
    /// A fitted slope under this (kg per week) is called flat: it would put the target years
    /// out, which is not a date anyone should be told.
    public static let minSlopeKgPerWeek = 0.05

    public enum Caveat: String, Codable, Hashable, Sendable {
        /// Fewer than `minSessions` sessions in the window — no slope, no date.
        case tooFewSessions
        /// The line is flat or falling — no date.
        case flatOrNegative
        /// The most recent session's e1RM already meets the target.
        case alreadyThere
        case ok
    }

    public struct Forecast: Codable, Hashable, Sendable {
        /// The day the fitted line crosses the target. Nil unless `caveat == .ok`.
        public var reachDate: Date?
        /// Weeks from `now` to `reachDate`. Nil unless `caveat == .ok`.
        public var weeksToTarget: Double?
        /// The fitted slope; 0 when too few sessions.
        public var slopeKgPerWeek: Double
        /// Weighted coefficient of determination, 0…1; 0 when too few sessions.
        public var r2: Double
        /// Sessions inside the window that the line was fitted to.
        public var sessions: Int
        /// The most recent session's e1RM in the window.
        public var currentE1RM: Double
        public var caveat: Caveat

        public init(
            reachDate: Date?, weeksToTarget: Double?, slopeKgPerWeek: Double, r2: Double,
            sessions: Int, currentE1RM: Double, caveat: Caveat
        ) {
            self.reachDate = reachDate
            self.weeksToTarget = weeksToTarget
            self.slopeKgPerWeek = slopeKgPerWeek
            self.r2 = r2
            self.sessions = sessions
            self.currentE1RM = currentE1RM
            self.caveat = caveat
        }
    }

    /// - Parameter points: one (session date, best e1RM that session) per session, any order.
    ///   Points after `now` or older than `windowWeeks` are ignored.
    /// - Returns: nil when nothing falls inside the window — there is nothing to say, not even
    ///   "too few sessions".
    public static func forecast(
        points: [(date: Date, e1rmKg: Double)], targetKg: Double, now: Date, calendar: Calendar
    ) -> Forecast? {
        let secondsPerWeek = 7.0 * 86_400
        let window = Double(windowWeeks) * secondsPerWeek
        let inWindow = points
            .filter { $0.e1rmKg > 0 && $0.date <= now && now.timeIntervalSince($0.date) <= window }
            .sorted { $0.date < $1.date }
        guard let latest = inWindow.last else { return nil }
        let current = latest.e1rmKg

        var forecast = Forecast(
            reachDate: nil, weeksToTarget: nil, slopeKgPerWeek: 0, r2: 0,
            sessions: inWindow.count, currentE1RM: current, caveat: .ok
        )
        guard inWindow.count >= minSessions else {
            forecast.caveat = .tooFewSessions
            return forecast
        }

        // x is weeks before now (≤ 0), so the intercept is the line's value today.
        let samples = inWindow.map { point -> (x: Double, y: Double, w: Double) in
            let ageWeeks = now.timeIntervalSince(point.date) / secondsPerWeek
            return (x: -ageWeeks, y: point.e1rmKg, w: pow(0.5, ageWeeks / halfLifeWeeks))
        }
        let fit = weightedFit(samples)
        forecast.slopeKgPerWeek = fit.slope
        forecast.r2 = fit.r2

        if current >= targetKg {
            forecast.caveat = .alreadyThere
            return forecast
        }
        guard fit.slope >= minSlopeKgPerWeek else {
            forecast.caveat = .flatOrNegative
            return forecast
        }
        // The line may already sit above the target today (a single low latest session under a
        // rising line); that is "any day now", not a date in the past.
        let weeks = max(0, (targetKg - fit.intercept) / fit.slope)
        forecast.weeksToTarget = weeks
        forecast.reachDate = calendar.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: now)
        return forecast
    }

    /// Weighted least squares: slope and intercept minimising Σ w·(y − (a + b·x))², plus the
    /// weighted R². A degenerate x spread (every session the same day) yields slope 0.
    static func weightedFit(_ samples: [(x: Double, y: Double, w: Double)]) -> (
        slope: Double, intercept: Double, r2: Double
    ) {
        let totalWeight = samples.reduce(0) { $0 + $1.w }
        guard totalWeight > 0 else { return (0, 0, 0) }
        let meanX = samples.reduce(0) { $0 + $1.w * $1.x } / totalWeight
        let meanY = samples.reduce(0) { $0 + $1.w * $1.y } / totalWeight
        let sxx = samples.reduce(0) { $0 + $1.w * ($1.x - meanX) * ($1.x - meanX) }
        let sxy = samples.reduce(0) { $0 + $1.w * ($1.x - meanX) * ($1.y - meanY) }
        let syy = samples.reduce(0) { $0 + $1.w * ($1.y - meanY) * ($1.y - meanY) }
        guard sxx > 0 else { return (0, meanY, 0) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let residual = samples.reduce(0) { total, sample in
            let predicted = intercept + slope * sample.x
            return total + sample.w * (sample.y - predicted) * (sample.y - predicted)
        }
        let r2 = syy > 0 ? max(0, min(1, 1 - residual / syy)) : 1
        return (slope, intercept, r2)
    }
}
