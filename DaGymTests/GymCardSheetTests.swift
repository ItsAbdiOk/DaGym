import Foundation
import SwiftData
import Testing
import VisionKit

@testable import DaGym

/// Pins the store/renderer/scanner contracts `GymCardSheet` leans on: one `lastUsedAt` stamp on
/// dismiss, a shared `CIContext`, and a readable reason when the camera scanner can't start.
@MainActor
@Suite("Gym card sheet")
struct GymCardSheetTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    @Test("markGymCardUsed stamps the given date so the card left showing on dismiss opens next")
    func markUsedStampsDate() throws {
        let store = try makeStore()
        let first = try #require(store.addGymCard(name: "A", value: "111", symbology: .code128))
        let second = try #require(store.addGymCard(name: "B", value: "222", symbology: .code128))
        let earlier = Date().addingTimeInterval(-3600)
        store.markGymCardUsed(id: second.id, at: earlier)
        store.markGymCardUsed(id: first.id)
        #expect(store.lastUsedGymCard()?.id == first.id)
        #expect(store.gymCards().first { $0.id == second.id }?.lastUsedAt == earlier)
    }

    @Test("BarcodeRenderer shares one CIContext across renders")
    func barcodeContextShared() {
        #expect(BarcodeRenderer.context === BarcodeRenderer.context)
        #expect(BarcodeRenderer.image(value: "42", symbology: .code128) != nil)
    }

    @Test("scanner start failures map to a reason the sheet can show")
    func scannerFailureMessages() {
        let restricted = GymCardScannerView.failureMessage(
            for: DataScannerViewController.ScanningUnavailable.cameraRestricted
        )
        #expect(restricted.contains("Camera access"))
        let unsupported = GymCardScannerView.failureMessage(
            for: DataScannerViewController.ScanningUnavailable.unsupported
        )
        #expect(unsupported.contains("can't scan"))
        let other = GymCardScannerView.failureMessage(for: CocoaError(.fileNoSuchFile))
        #expect(other == "The camera couldn't start.")
    }
}
