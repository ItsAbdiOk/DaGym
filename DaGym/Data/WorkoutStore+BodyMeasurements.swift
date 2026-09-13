import Foundation
import SwiftData

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
}
