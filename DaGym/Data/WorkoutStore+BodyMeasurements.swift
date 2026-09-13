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
    /// `HealthSyncService.pullBodyweight()`'s "newer than ours" check and any future Home display.
    func latestBodyMeasurement() -> BodyMeasurementModel? {
        var descriptor = FetchDescriptor<BodyMeasurementModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Logs one bodyweight reading — a manual keypad entry from `BodyweightSheet`, or a pull from
    /// Apple Health (`source: "health"`) — and persists it immediately.
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
        return ((try? context.fetch(descriptor)) ?? []).compactMap(Self.measurementInfo)
    }

    /// The most recent readings, newest first, for the "recent measurements" list.
    func recentBodyMeasurements(limit: Int = 20) -> [BodyMeasurementInfo] {
        var descriptor = FetchDescriptor<BodyMeasurementModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).compactMap(Self.measurementInfo)
    }

    private static func measurementInfo(_ model: BodyMeasurementModel) -> BodyMeasurementInfo? {
        guard let kg = model.bodyweightKg else { return nil }
        return BodyMeasurementInfo(id: model.id, date: model.date, kg: kg, source: model.source)
    }
}
