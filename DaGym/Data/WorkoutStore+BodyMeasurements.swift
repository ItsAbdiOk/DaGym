import Foundation
import SwiftData

/// One bodyweight reading, for `BodyView`'s chart and recent-measurements list.
struct BodyMeasurementInfo: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var kg: Double
    /// "manual" or "health".
    var source: String
}

extension WorkoutStore {
    /// The most recent bodyweight reading across every source (manual or Apple Health), for
    /// PR evaluation and the Health calorie estimate.
    /// - Parameter asOf: when passed, only readings on or before this date are considered — the
    ///   bodyweight as it was known at a past workout, for PR evaluation (A7).
    func latestBodyMeasurement(asOf: Date? = nil) -> BodyMeasurementModel? {
        var descriptor: FetchDescriptor<BodyMeasurementModel>
        if let asOf {
            descriptor = FetchDescriptor<BodyMeasurementModel>(
                predicate: #Predicate { $0.date <= asOf }, sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<BodyMeasurementModel>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        }
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor)
    }

    /// Logs one bodyweight reading and persists it immediately.
    ///
    /// Only ever manual entries now: bodyweight held in Apple Health is read live by
    /// `HealthInsightsService.mergedBodyweightSeries` rather than copied in here, because copying
    /// it would put HealthKit-derived data in the CloudKit-mirrored store (App Store Guideline
    /// 5.1.3). `source` stays on the model for the rows written by the build that did copy it,
    /// which `WorkoutStore.purgeHealthDerivedRowsFromMainStore()` clears out on next launch.
    @discardableResult
    func logBodyweight(kg: Double, date: Date = Date(), source: String = "manual") -> BodyMeasurementModel {
        let model = BodyMeasurementModel(date: date, bodyweightKg: kg, source: source)
        context.insert(model)
        save()
        return model
    }

    /// Bodyweight readings from the last `days`, oldest first, for the `BodyView` chart.
    func bodyweightSeries(days: Int = 90) -> [BodyMeasurementInfo] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let predicate = #Predicate<BodyMeasurementModel> { $0.date >= since }
        let descriptor = FetchDescriptor<BodyMeasurementModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return fetch(descriptor).compactMap(Self.measurementInfo)
    }

    /// Manual-only bodyweight readings from the last `days`, oldest first — the local half of
    /// `HealthInsightsService.mergedBodyweightSeries`'s day-level merge with live Health history.
    /// The `source == "manual"` filter also skips any leftover `"health"` rows written by the
    /// build that copied Health into this store, before `purgeHealthDerivedRowsFromMainStore()`
    /// clears them on next launch.
    func manualBodyweightSeries(days: Int = 90) -> [BodyMeasurementInfo] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let predicate = #Predicate<BodyMeasurementModel> { $0.date >= since && $0.source == "manual" }
        let descriptor = FetchDescriptor<BodyMeasurementModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return fetch(descriptor).compactMap(Self.measurementInfo)
    }

    /// The most recent readings, newest first, for the "recent measurements" list.
    func recentBodyMeasurements(limit: Int = 20) -> [BodyMeasurementInfo] {
        var descriptor = FetchDescriptor<BodyMeasurementModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return fetch(descriptor).compactMap(Self.measurementInfo)
    }

    /// Rewrites one reading's weight (a Body reading row tapped and corrected). Only manual
    /// rows: a Health-sourced row is Health's to change. Returns false when nothing was edited.
    @discardableResult
    func updateBodyMeasurement(id: UUID, kg: Double) -> Bool {
        guard let model = bodyMeasurement(id: id), model.source == "manual" else { return false }
        model.bodyweightKg = kg
        save()
        return true
    }

    /// Removes one manual reading. Returns false when it was not found or not manual.
    @discardableResult
    func deleteBodyMeasurement(id: UUID) -> Bool {
        guard let model = bodyMeasurement(id: id), model.source == "manual" else { return false }
        context.delete(model)
        save()
        return true
    }

    private func bodyMeasurement(id: UUID) -> BodyMeasurementModel? {
        var descriptor = FetchDescriptor<BodyMeasurementModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor)
    }

    private static func measurementInfo(_ model: BodyMeasurementModel) -> BodyMeasurementInfo? {
        guard let kg = model.bodyweightKg else { return nil }
        return BodyMeasurementInfo(id: model.id, date: model.date, kg: kg, source: model.source)
    }
}
