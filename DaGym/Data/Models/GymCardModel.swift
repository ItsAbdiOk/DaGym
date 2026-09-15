import Foundation
import SwiftData

/// A gym's check-in card: the scanned barcode's payload and symbology, nothing else — the
/// image is regenerated from these on every show (features.md adopt 6). CloudKit-legal.
@Model
final class GymCardModel {
    var id = UUID()
    var name: String = ""
    var value: String = ""
    /// `GymCardSymbology` raw value.
    var symbology: String = "qr"
    var sortOrder: Int = 0
    var createdAt = Date()
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(), name: String = "", value: String = "", symbology: String = "qr",
        sortOrder: Int = 0, createdAt: Date = Date(), lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.symbology = symbology
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
