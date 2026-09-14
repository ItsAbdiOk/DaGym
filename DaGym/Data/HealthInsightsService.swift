import Foundation

/// Read-only Apple Health insights for the UI: body composition, recovery context and the
/// external-workout import queue. Deliberately separate from `HealthSyncService` (which owns
/// Health *writes* plus bodyweight/workout sync) — this type only ever reads, and every read is
/// gated by its own `Preferences` toggle so nothing reaches Health that the toggle didn't grant.
/// Every method returns `nil`/empty rather than a zero when there's nothing to show, so a caller
/// can hide the whole section instead of rendering an empty row (App Store review risk: reading
/// a HealthKit type the UI never surfaces gets an app rejected).
@MainActor
@Observable
final class HealthInsightsService {
    private let healthStore: any HealthStoring
    private let workoutStore: WorkoutStore
    private let preferences: Preferences

    init(
        healthStore: any HealthStoring = HealthKitStore(), workoutStore: WorkoutStore,
        preferences: Preferences
    ) {
        self.healthStore = healthStore
        self.workoutStore = workoutStore
        self.preferences = preferences
    }

    var isAvailable: Bool { healthStore.isAvailable }

    // MARK: - Body composition (Body screen)

    struct BodyComposition {
        var bodyFat: HealthSample?
        var bodyFatHistory: [HealthSample]
        var leanMass: HealthSample?
        var leanMassHistory: [HealthSample]
        var height: HealthSample?

        var isEmpty: Bool { bodyFat == nil && leanMass == nil && height == nil }
    }

    /// Nil when the toggle is off, Health is unavailable, or Health simply has none of these
    /// three readings yet.
    func bodyComposition(days: Int = 365) async -> BodyComposition? {
        guard preferences.healthReadBodyComposition, isAvailable else { return nil }
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        async let bodyFat = try? healthStore.latestBodyFatPercentage()
        async let bodyFatHistory = (try? healthStore.bodyFatHistory(from: since, to: Date())) ?? []
        async let leanMass = try? healthStore.latestLeanBodyMass()
        async let leanMassHistory = (try? healthStore.leanBodyMassHistory(from: since, to: Date())) ?? []
        async let height = try? healthStore.latestHeight()
        let composition = await BodyComposition(
            bodyFat: bodyFat, bodyFatHistory: bodyFatHistory, leanMass: leanMass,
            leanMassHistory: leanMassHistory, height: height
        )
        return composition.isEmpty ? nil : composition
    }

    // MARK: - Recovery context (Recovery map)

    struct RecoverySignals {
        var restingHeartRate: HealthSample?
        /// Average of every resting-HR sample in the trailing 30 days *before* the latest one —
        /// purely descriptive context for `RecoveryMapView`'s trend text, never a score.
        var restingHeartRateAverage30Day: Double?
        var hrv: HealthSample?
        var hrvAverage30Day: Double?
        var sleep: HealthSleepInterval?

        var isEmpty: Bool { restingHeartRate == nil && hrv == nil && sleep == nil }
    }

    /// Plain recent values only — never a readiness score or a training recommendation. Nil when
    /// the toggle is off, Health is unavailable, or there's nothing to show.
    func recoverySignals() async -> RecoverySignals? {
        guard preferences.healthReadRecovery, isAvailable else { return nil }
        let now = Date()
        let since30 = now.addingTimeInterval(-30 * 86_400)
        // Sleep intervals can straddle midnight and post hours after waking, so look back 2 days
        // for "last night" rather than a tight window.
        let sinceSleep = now.addingTimeInterval(-2 * 86_400)
        async let rhrHistory = (try? healthStore.restingHeartRate(from: since30, to: now)) ?? []
        async let hrvHistory = (try? healthStore.hrv(from: since30, to: now)) ?? []
        async let sleepIntervals = (try? healthStore.sleep(from: sinceSleep, to: now)) ?? []
        let rhr = await rhrHistory
        let hrv = await hrvHistory
        let sleep = await sleepIntervals
        let signals = RecoverySignals(
            restingHeartRate: rhr.last, restingHeartRateAverage30Day: Self.average(rhr.dropLast()),
            hrv: hrv.last, hrvAverage30Day: Self.average(hrv.dropLast()),
            sleep: Self.longestInterval(sleep)
        )
        return signals.isEmpty ? nil : signals
    }

    /// The longest asleep interval in the window — the closest proxy for "last night" without a
    /// full sleep-stage model, and robust to a short nap also landing in the query window.
    private static func longestInterval(_ intervals: [HealthSleepInterval]) -> HealthSleepInterval? {
        intervals.max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
    }

    private static func average<C: Collection>(_ samples: C) -> Double? where C.Element == HealthSample {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }

    // MARK: - External workout import (History / Settings)

    /// Everything Health has logged that DaGym hasn't imported yet — the "N workouts found in
    /// Health" row's count and list. Empty (never an error) when the toggle is off, Health is
    /// unavailable, or there's genuinely nothing new.
    func pendingExternalWorkouts(days: Int = 30) async -> [HealthExternalWorkout] {
        guard preferences.healthImportWorkouts, isAvailable else { return [] }
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        let external = (try? await healthStore.externalStrengthWorkouts(since: since)) ?? []
        return external.filter { !workoutStore.hasWorkout(healthKitID: $0.uuid) }
    }

    /// Imports every pending external workout. Only ever called from an explicit user tap
    /// (`SettingsView`'s import row) — this never runs on its own, so nothing lands in History
    /// behind the user's back. Returns what actually landed, for a confirmation.
    @discardableResult
    func importPendingExternalWorkouts() async -> [WorkoutModel] {
        let pending = await pendingExternalWorkouts()
        return pending.compactMap { workoutStore.importExternalWorkout($0) }
    }

    // MARK: - Bodyweight chart merge (Body screen)

    /// Merges Health bodyweight history with our own manual entries, one point per calendar day,
    /// preferring the manual entry when both exist for the same day. Pure and synchronous, so
    /// it's the directly unit-testable core of `mergedBodyweightSeries` below — this is what
    /// keeps a weight we wrote to Health ourselves (`HealthSyncService.pushBodyweight`) from ever
    /// plotting twice.
    static func mergeBodyweightSeries(
        manual: [BodyMeasurementInfo], health: [HealthSample], calendar: Calendar = .current
    ) -> [BodyMeasurementInfo] {
        var byDay: [Date: BodyMeasurementInfo] = [:]
        for sample in health {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day] = BodyMeasurementInfo(
                id: UUID(), date: sample.date, kg: sample.value, source: "health"
            )
        }
        for entry in manual {
            let day = calendar.startOfDay(for: entry.date)
            byDay[day] = entry // Manual always wins for a day both sources cover.
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Manual entries merged with live Health bodyweight history, for `BodyView`'s chart. Manual
    /// only (no Health call) when bodyweight sync is off, so nothing reaches Health the toggle
    /// didn't grant.
    func mergedBodyweightSeries(days: Int = 90) async -> [BodyMeasurementInfo] {
        let manual = workoutStore.manualBodyweightSeries(days: days)
        guard preferences.healthSyncBodyweight, isAvailable else { return manual }
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        let health = (try? await healthStore.bodyMassHistory(from: since, to: Date())) ?? []
        return Self.mergeBodyweightSeries(manual: manual, health: health)
    }
}
