import GymCore
import UIKit

/// The program half of `PlanPDFRenderer` (plan.md §6.8 P7): a cover page, then one page per
/// week. Pages: `1 + weeks` for a program whose weeks fit their sheet; a week with more
/// routines than fit continues onto an extra page headed "Week n (continued)".
extension PlanPDFRenderer {
    static func layoutProgram(
        _ program: PlanProgram, routines: [PlanRoutine], into pages: PlanPDFPages, unit: WeightUnit
    ) {
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cycle = program.routineIDs.compactMap { byID[$0] }
        let weeks = program.programWeeks.sorted { $0.index < $1.index }
        layoutCover(program, cycle: cycle, weeks: weeks, into: pages, unit: unit)
        if weeks.isEmpty {
            // A file written before week kinds existed: every week is a normal one.
            for index in 1...max(program.weeks, 1) {
                let week = PlanProgramWeek(index: index, kind: "normal")
                layoutWeek(week, of: program, cycle: cycle, into: pages, unit: unit)
            }
        } else {
            for week in weeks { layoutWeek(week, of: program, cycle: cycle, into: pages, unit: unit) }
        }
    }

    // MARK: - Cover

    private static func layoutCover(
        _ program: PlanProgram, cycle: [PlanRoutine], weeks: [PlanProgramWeek], into pages: PlanPDFPages,
        unit: WeightUnit
    ) {
        pages.beginPage()
        pages.continuationHeader = nil
        let width = pages.contentWidth
        let uniqueCount = Set(cycle.map(\.id)).count
        pages.add(height: 40) { y in
            draw(program.name.uppercased(), at: CGPoint(x: margin, y: y), font: titleFont)
        }
        pages.add(height: 40) { y in
            draw(
                "\(program.weeks) week\(program.weeks == 1 ? "" : "s") · \(uniqueCount) routine" +
                    (uniqueCount == 1 ? "" : "s"),
                at: CGPoint(x: margin, y: y), font: subtitleFont, color: .darkGray
            )
        }
        pages.add(height: rowHeight) { y in
            draw("SCHEDULE", at: CGPoint(x: margin, y: y), font: sectionFont)
        }
        let dayColumn = width * 0.4
        for (index, routine) in cycle.enumerated() {
            pages.add(height: rowHeight) { y in
                draw("Day \(index + 1)", at: CGPoint(x: margin, y: y), font: bodyFont)
                draw(routine.name, at: CGPoint(x: margin + dayColumn, y: y), font: bodyFont)
            }
        }
        pages.space(12)
        pages.add(height: rowHeight) { y in draw("WEEKS", at: CGPoint(x: margin, y: y), font: sectionFont) }
        pages.add(height: 44) { y in drawWeekGrid(weeks, at: CGPoint(x: margin, y: y), width: width) }
        pages.space(12)
        layoutProgressionRules(cycle, into: pages, unit: unit)
    }

    /// One paragraph per distinct routine — its rule's name and the same one-line "why" the
    /// routine builder shows — plus any per-exercise override under it.
    private static func layoutProgressionRules(
        _ cycle: [PlanRoutine], into pages: PlanPDFPages, unit: WeightUnit
    ) {
        let width = pages.contentWidth
        pages.add(height: rowHeight) { y in
            draw("PROGRESSION", at: CGPoint(x: margin, y: y), font: sectionFont)
        }
        var seen: Set<UUID> = []
        for routine in cycle where seen.insert(routine.id).inserted {
            let rule = ProgressionRuleCoding.decode(routine.ruleJSON)
            let text = "\(routine.name) — \(ruleName(for: routine))" +
                (rule.map { ": \($0.explanation(unit: unit))" } ?? "")
            addParagraph(text, font: bodyFont, color: .black, width: width, into: pages)
            for exercise in routine.exercises.sorted(by: { $0.order < $1.order }) {
                guard let override = ProgressionRuleCoding.decode(exercise.ruleJSON) else { continue }
                let line = "    \(exercise.exerciseName) · \(override.displayName): " +
                    override.explanation(unit: unit)
                addParagraph(line, font: bodyFont, color: .darkGray, width: width, into: pages)
            }
        }
    }

    private static func addParagraph(
        _ text: String, font: UIFont, color: UIColor, width: CGFloat, into pages: PlanPDFPages
    ) {
        let height = paragraphHeight(text, width: width, font: font)
        pages.add(height: height) { y in
            drawParagraph(text, at: CGPoint(x: margin, y: y), width: width, font: font, color: color)
        }
    }

    private static func drawWeekGrid(_ weeks: [PlanProgramWeek], at origin: CGPoint, width: CGFloat) {
        let columnWidth = width / CGFloat(max(weeks.count, 1))
        for (offset, week) in weeks.enumerated() {
            let x = origin.x + CGFloat(offset) * columnWidth
            draw("W\(week.index)", at: CGPoint(x: x, y: origin.y), font: headerFont, color: .darkGray)
            draw(week.kind.capitalized, at: CGPoint(x: x, y: origin.y + 18), font: bodyFont)
        }
    }

    // MARK: - Week pages

    private static func layoutWeek(
        _ week: PlanProgramWeek, of program: PlanProgram, cycle: [PlanRoutine], into pages: PlanPDFPages,
        unit: WeightUnit
    ) {
        pages.beginPage()
        let title = "WEEK \(week.index) OF \(program.weeks)"
        pages.continuationHeader = { pages in
            pages.add(height: 32) { y in
                draw("\(title) (CONTINUED)", at: CGPoint(x: margin, y: y), font: sectionFont)
            }
        }
        pages.add(height: 40) { y in draw(title, at: CGPoint(x: margin, y: y), font: titleFont) }
        pages.add(height: 32) { y in
            draw(weekSubtitle(week), at: CGPoint(x: margin, y: y), font: subtitleFont, color: .darkGray)
        }
        guard week.kind != ProgramWeekKind.rest.rawValue else {
            pages.add(height: rowHeight) { y in
                draw(
                    "No sessions planned — recover, then start the next week.",
                    at: CGPoint(x: margin, y: y), font: bodyFont
                )
            }
            return
        }
        let width = pages.contentWidth
        for (index, routine) in cycle.enumerated() {
            pages.space(10)
            pages.add(height: rowHeight) { y in
                draw(
                    "DAY \(index + 1) · \(routine.name.uppercased())", at: CGPoint(x: margin, y: y),
                    font: sectionFont
                )
            }
            layoutExerciseTable(routine, into: pages, width: width, rowHeight: compactRowHeight, unit: unit)
        }
    }

    /// "Deload week" carries the fractions the engine prescribes, so a printed sheet says how
    /// much lighter — not just that it is.
    static func weekSubtitle(_ week: PlanProgramWeek) -> String {
        switch ProgramWeekKind(rawValue: week.kind) ?? .normal {
        case .normal:
            return "Normal week · full sets and loads as planned"
        case .deload:
            let sets = Int((TrainingConstants.deloadSetsFraction * 100).rounded())
            let load = Int((TrainingConstants.deloadLoadFraction * 100).rounded())
            return "Deload week · about \(sets)% of the sets at \(load)% of the load"
        case .rest:
            return "Rest week"
        }
    }
}
