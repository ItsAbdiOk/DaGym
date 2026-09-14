import Foundation
@testable import GymCore

/// Shared fixtures for the Coach rule tests: a fixed UTC/Monday-first calendar (so week math is
/// reproducible regardless of the machine running the tests) and an ISO8601 date parser, the same
/// pattern `SeriesTests.swift`'s `BalanceWindowTests` uses.
enum CoachTestSupport {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    static func daysAgo(_ days: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    static func daysFromNow(_ days: Int, from now: Date) -> Date {
        daysAgo(-days, from: now)
    }
}
