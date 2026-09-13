import Foundation
import SwiftData

/// A single bodyweight (or other body metric) reading.
@Model
final class BodyMeasurementModel {
    var id: UUID = UUID()
    var date: Date = Date()
    var bodyweightKg: Double?
    var source: String = "manual"

    init(id: UUID = UUID(), date: Date = Date(), bodyweightKg: Double? = nil, source: String = "manual") {
        self.id = id
        self.date = date
        self.bodyweightKg = bodyweightKg
        self.source = source
    }
}
