import Foundation
import GymCore
import Testing
import UIKit

@testable import DaGym

@Suite("Share: workout summary card model")
struct ShareCardModelTests {
    private func summary(prs: [PersonalRecordInfo] = [], distance: Double = 0) -> WorkoutSummary {
        WorkoutSummary(
            durationSeconds: 3124, volumeKg: 6840, setsDone: 18, prs: prs,
            musclesHit: [.chest: 1, .triceps: 0.6, .delts: 0.4, .biceps: 0.1],
            distanceMeters: distance
        )
    }

    private var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    @Test("volume is thin-space grouped in the user's unit: kg and lb")
    func volumeFormatting() {
        let kg = ShareCardModel(
            summary: summary(), title: "Push A", date: fixedDate, unit: .kg, distanceUnit: .km
        )
        #expect(kg.volumeText == "6\u{2009}840 kg")
        let lb = ShareCardModel(
            summary: summary(), title: "Push A", date: fixedDate, unit: .lb, distanceUnit: .mi
        )
        // 6 840 kg × 2.20462 = 15 079.6 → no decimals.
        #expect(lb.volumeText == "15\u{2009}080 lb")
        #expect(kg.durationText == "52:04")
        #expect(kg.setsText == "18")
        #expect(kg.dateText.contains("2026"))
        #expect(kg.distanceText == nil)
    }

    @Test("distance joins the message only when a run is in the session")
    func distanceLine() {
        let model = ShareCardModel(
            summary: summary(distance: 5000), title: "Run", date: fixedDate, unit: .kg, distanceUnit: .km
        )
        #expect(model.distanceText == "5.0 km")
        #expect(model.shareMessage.contains("5.0 km"))
    }

    @Test("PR headline and lines compose from the summary's records")
    func prLines() {
        let prs = [
            PersonalRecordInfo(exerciseName: "Bench", line: "82.5 × 8 (e1RM 102.5)"),
            PersonalRecordInfo(exerciseName: "Squat", line: "120 × 5")
        ]
        let model = ShareCardModel(
            summary: summary(prs: prs), title: "Push A", date: fixedDate, unit: .kg, distanceUnit: .km
        )
        #expect(model.prHeadline == "2 Personal Records")
        #expect(model.prLines == ["Bench · 82.5 × 8 (e1RM 102.5)", "Squat · 120 × 5"])
        #expect(model.shareSubject == "Push A · DaGym")
        #expect(model.shareMessage == "Push A — 52:04, 18 sets, 6\u{2009}840 kg · 2 personal records")
        #expect(ShareCardModel.prHeadline(count: 1) == "1 Personal Record")
    }

    @Test("no PRs: no headline, no PR line in the message")
    func emptyPRs() {
        let model = ShareCardModel(
            summary: summary(), title: "Push A", date: fixedDate, unit: .kg, distanceUnit: .km
        )
        #expect(model.prHeadline == nil)
        #expect(model.prLines.isEmpty)
        #expect(model.shareMessage == "Push A — 52:04, 18 sets, 6\u{2009}840 kg")
    }

    @Test("top muscles are the three largest shares, as percentages of the total")
    func topMuscles() {
        let model = ShareCardModel(
            summary: summary(), title: "Push A", date: fixedDate, unit: .kg, distanceUnit: .km
        )
        #expect(model.topMuscles.map(\.muscle) == [.chest, .triceps, .delts])
        // 1 / 2.1 = 47.6 % → "48%".
        #expect(model.topMuscles.first?.percentText == "48%")
        #expect(ShareCardModel.topMuscles([:]).isEmpty)
    }
}

@MainActor
@Suite("Share: workout summary card render", .serialized)
struct ShareCardRenderTests {
    private var preferences: Preferences {
        Preferences(suite: UserDefaults(suiteName: "ShareCardRenderTests") ?? .standard)
    }

    @Test("ImageRenderer produces a 1080×1920 story and a 1080×1080 square at scale 1")
    func rendersBothFormats() {
        let model = ShareCardModel(
            summary: WorkoutSummary(
                durationSeconds: 1800, volumeKg: 4000, setsDone: 12,
                prs: [PersonalRecordInfo(exerciseName: "Bench", line: "80 × 8")],
                musclesHit: [.chest: 1, .triceps: 0.5]
            ),
            title: "Push A", unit: .kg, distanceUnit: .km
        )
        let preferences = preferences
        for format in WorkoutShareCardFormat.allCases {
            let image = WorkoutShareCardRenderer.render(model, format: format, preferences: preferences)
            #expect(image != nil)
            #expect(image?.scale == 1)
            #expect(image?.size == format.size)
            #expect((image?.pngData()?.count ?? 0) > 0)
        }
        let flat = WorkoutShareCardRenderer.render(
            model, format: .square, preferences: preferences, reduceTransparency: true
        )
        #expect(flat?.size == CGSize(width: 1080, height: 1080))
    }
}
