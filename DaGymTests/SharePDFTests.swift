import Foundation
import GymCore
import PDFKit
import SwiftData
import Testing

@testable import DaGym

@Suite("Share: program PDF export")
struct SharePDFTests {
    private func routine(
        _ name: String, id: UUID, rule: ProgressionRule, weightKg: Double? = nil
    ) -> PlanRoutine {
        PlanRoutine(
            id: id, name: name, ruleJSON: ProgressionRuleCoding.encode(rule),
            exercises: [
                PlanRoutineExercise(
                    order: 0, exerciseName: "\(name) Bench Press",
                    sets: (0..<3).map {
                        PlanSet(
                            order: $0, kind: "working", targetReps: 6, targetRepsHigh: 8,
                            targetWeightKg: weightKg
                        )
                    }
                ),
                PlanRoutineExercise(
                    order: 1, exerciseName: "\(name) Row", restOverrideSeconds: 90,
                    sets: [PlanSet(order: 0, kind: "working", targetReps: 10)]
                )
            ]
        )
    }

    private func document(weeks: [String], weightKg: Double? = nil) -> PlanDocument {
        let pushID = UUID()
        let pullID = UUID()
        let push = routine(
            "Push", id: pushID, rule: .doubleProgression(low: 6, high: 8, incrementKg: 2.5),
            weightKg: weightKg
        )
        let pull = routine("Pull", id: pullID, rule: .linear(incrementKg: 2.5), weightKg: weightKg)
        let program = PlanProgram(
            id: UUID(), name: "Upper Block", weeks: weeks.count, routineIDs: [pushID, pullID, pushID],
            programWeeks: weeks.enumerated().map { PlanProgramWeek(index: $0.offset + 1, kind: $0.element) }
        )
        return PlanDocument(
            exportedAt: Date(), appVersion: "1.0", routines: [push, pull], program: program
        )
    }

    private func pdf(_ document: PlanDocument, unit: WeightUnit = .kg) throws -> PDFDocument {
        try #require(PDFDocument(data: PlanPDFRenderer.render(document, unit: unit)))
    }

    @Test("a program renders 1 + weeks pages: cover, then one per week")
    func pageCountIsCoverPlusWeeks() throws {
        let four = try pdf(document(weeks: ["normal", "normal", "normal", "deload"]))
        #expect(four.pageCount == 5)
        let two = try pdf(document(weeks: ["normal", "rest"]))
        #expect(two.pageCount == 3)
    }

    @Test("week kinds, the schedule, exercise names and the rule explanations are in the text")
    func textContainsWeeksAndExercises() throws {
        let doc = try pdf(document(weeks: ["normal", "deload", "rest"]))
        let text = try #require(doc.string)
        #expect(text.contains("UPPER BLOCK"))
        #expect(text.contains("3 weeks · 2 routines"))
        #expect(text.contains("Day 3"))
        #expect(text.contains("WEEK 2 OF 3"))
        #expect(text.contains("Deload week"))
        #expect(text.contains("Rest week"))
        #expect(text.contains("Push Bench Press"))
        #expect(text.contains("Pull Row"))
        #expect(text.contains("3 × 6–8"))
        #expect(text.contains("Double progression: Climbs reps from 6 to 8"))
        #expect(text.contains("Page 4 of 4"))
        // A rest week lists no sessions.
        let restPage = try #require(doc.page(at: 3)?.string)
        #expect(restPage.contains("No sessions planned"))
        #expect(!restPage.contains("Bench Press"))
    }

    @Test("planned weights and rule increments render in lb when asked")
    func rendersInPounds() throws {
        let lb = try #require(try pdf(document(weeks: ["normal"], weightKg: 100), unit: .lb).string)
        #expect(lb.contains("220.5 lb"))
        #expect(lb.contains("adds 5.5 lb"))
        let kg = try #require(try pdf(document(weeks: ["normal"], weightKg: 100)).string)
        #expect(kg.contains("100 kg"))
        #expect(!kg.contains("lb"))
    }

    @Test("a routine-only document keeps one page per routine, with page numbers")
    func routineDocumentPages() throws {
        let doc = PlanDocument(
            exportedAt: Date(), appVersion: "1.0",
            routines: [
                routine("Push", id: UUID(), rule: .linear(incrementKg: 2.5)),
                routine("Pull", id: UUID(), rule: .linear(incrementKg: 2.5))
            ]
        )
        let pdf = try pdf(doc)
        #expect(pdf.pageCount == 2)
        #expect(pdf.string?.contains("Page 2 of 2") == true)
    }

    /// The `.gymplan` file strips the lifter's working weights (they go to someone else); their
    /// own PDF printout keeps them. Same store, same routine, one flag apart.
    @Test("the lifter's own PDF carries target weights only when the export is asked for them")
    @MainActor
    func ownPrintoutIncludesWeightsOnRequest() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 100)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push", exercises: [draft])

        let own = try #require(
            PlanShareService.exportRoutine(id: routine.id, context: context, includeWeights: true)
        )
        #expect(try pdf(own).string?.contains("100 kg") == true)

        let shared = try #require(PlanShareService.exportRoutine(id: routine.id, context: context))
        #expect(try pdf(shared).string?.contains("100 kg") == false)
        #expect(shared.routines.first?.exercises.first?.sets.first?.targetWeightKg == nil)
    }

    @Test("cardio and timed targets print as a clock time and a distance in the lifter's unit, RPE as itself")
    func cardioAndRPETargets() {
        func exercise(_ set: PlanSet) -> PlanRoutineExercise {
            PlanRoutineExercise(order: 0, exerciseName: "Run", sets: [set])
        }
        let run = exercise(PlanSet(order: 0, kind: "working", targetSeconds: 1_200))
        #expect(PlanPDFRenderer.targetText(run, unit: .kg) == "20:00")
        let distance = exercise(
            PlanSet(order: 0, kind: "working", targetSeconds: 3_600, targetDistanceMeters: 5_000)
        )
        #expect(PlanPDFRenderer.targetText(distance, unit: .kg) == "5.00 km · 1:00:00")
        #expect(PlanPDFRenderer.targetText(distance, unit: .lb) == "3.11 mi · 1:00:00")
        let rpe = exercise(PlanSet(order: 0, kind: "working", targetRPE: 8.5))
        #expect(PlanPDFRenderer.targetText(rpe, unit: .kg) == "RPE 8.5")
        let wholeRPE = exercise(PlanSet(order: 0, kind: "working", targetRPE: 8))
        #expect(PlanPDFRenderer.targetText(wholeRPE, unit: .kg) == "RPE 8")
    }

    @Test("deload subtitle names the engine's set and load fractions")
    func deloadSubtitle() {
        #expect(PlanPDFRenderer.weekSubtitle(PlanProgramWeek(index: 2, kind: "deload")).contains("60%"))
        #expect(PlanPDFRenderer.weekSubtitle(PlanProgramWeek(index: 2, kind: "deload")).contains("90%"))
        #expect(PlanPDFRenderer.weekSubtitle(PlanProgramWeek(index: 2, kind: "rest")) == "Rest week")
    }
}
