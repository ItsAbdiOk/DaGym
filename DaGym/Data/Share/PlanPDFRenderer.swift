import GymCore
import UIKit

/// Page size for a printed plan sheet — both render at 72 dpi points, matching
/// `UIGraphicsPDFRenderer`'s coordinate space.
enum PlanPDFPageSize {
    case a4
    case letter

    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595.2, height: 841.8)
        case .letter: CGSize(width: 612, height: 792)
        }
    }
}

/// Renders a clean, printable routine/program sheet from a `PlanDocument` (plan.md §6.8): one
/// page per routine (title, exercise table with superset brackets) plus, for a program export, a
/// final week-grid page. Pure UIKit (`UIGraphicsPDFRenderer`), no SwiftUI dependency, so it can
/// run off the main thread. Typography mirrors `DGFont`'s Barlow families.
enum PlanPDFRenderer {
    private static let margin: CGFloat = 40
    private static let rowHeight: CGFloat = 28
    private static let columnWidths: [CGFloat] = [0.34, 0.16, 0.18, 0.12, 0.20]

    static func render(
        _ document: PlanDocument, pageSize: PlanPDFPageSize = .a4, unit: WeightUnit = .kg
    ) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize.size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for routine in document.routines {
                context.beginPage()
                drawRoutine(routine, in: bounds, unit: unit)
            }
            if let program = document.program {
                context.beginPage()
                drawProgram(program, routines: document.routines, in: bounds)
            }
        }
    }

    // MARK: - Routine page

    private static func drawRoutine(_ routine: PlanRoutine, in bounds: CGRect, unit: WeightUnit) {
        let width = bounds.width - margin * 2
        var y = margin
        draw(routine.name.uppercased(), at: CGPoint(x: margin, y: y), font: titleFont, color: .black)
        y += 40
        draw(subtitle(for: routine), at: CGPoint(x: margin, y: y), font: subtitleFont, color: .darkGray)
        y += 32
        drawTableHeader(at: CGPoint(x: margin, y: y), width: width)
        y += rowHeight
        var lastGroup: Int?
        for exercise in routine.exercises.sorted(by: { $0.order < $1.order }) {
            let isSupersetStart = exercise.supersetGroup != nil && exercise.supersetGroup != lastGroup
            if isSupersetStart { drawSupersetMarker(at: CGPoint(x: margin - 14, y: y), height: rowHeight) }
            drawExerciseRow(exercise, at: CGPoint(x: margin, y: y), width: width, unit: unit)
            lastGroup = exercise.supersetGroup
            y += rowHeight
        }
    }

    private static func subtitle(for routine: PlanRoutine) -> String {
        let count = routine.exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s") · " +
            "\(ProgressionRuleCoding.decode(routine.ruleJSON)?.displayName ?? routine.progressionRule)"
    }

    private static func drawTableHeader(at origin: CGPoint, width: CGFloat) {
        let titles = ["Exercise", "Sets × Reps", "Target", "Rest", "Notes"]
        drawRow(titles, at: origin, width: width, font: headerFont, color: .darkGray)
        let lineY = origin.y + rowHeight - 6
        drawLine(from: CGPoint(x: origin.x, y: lineY), to: CGPoint(x: origin.x + width, y: lineY))
    }

    private static func drawExerciseRow(
        _ exercise: PlanRoutineExercise, at origin: CGPoint, width: CGFloat, unit: WeightUnit
    ) {
        let cells = [
            exercise.exerciseName, setsRepsText(exercise), targetText(exercise, unit: unit),
            restText(exercise.restOverrideSeconds), exercise.note
        ]
        drawRow(cells, at: origin, width: width, font: bodyFont, color: .black)
    }

    private static func setsRepsText(_ exercise: PlanRoutineExercise) -> String {
        let sets = exercise.sets.sorted { $0.order < $1.order }
        guard let first = sets.first else { return "\(sets.count) × –" }
        let reps: String
        if let low = first.targetReps, let high = first.targetRepsHigh, high != low {
            reps = "\(low)–\(high)"
        } else if let low = first.targetReps {
            reps = "\(low)"
        } else {
            reps = "–"
        }
        return "\(sets.count) × \(reps)"
    }

    private static func targetText(_ exercise: PlanRoutineExercise, unit: WeightUnit) -> String {
        guard let first = exercise.sets.min(by: { $0.order < $1.order }) else { return "–" }
        if let weight = first.targetWeightKg { return "\(unit.format(kg: weight)) \(unit.symbol)" }
        if let rpe = first.targetRPE { return "RPE \(WeightFormat.kg(rpe))" }
        if let seconds = first.targetSeconds { return "\(seconds)s" }
        return "–"
    }

    private static func restText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Program page

    private static func drawProgram(_ program: PlanProgram, routines: [PlanRoutine], in bounds: CGRect) {
        let width = bounds.width - margin * 2
        var y = margin
        draw(program.name.uppercased(), at: CGPoint(x: margin, y: y), font: titleFont, color: .black)
        y += 40
        draw(
            "\(program.weeks) week\(program.weeks == 1 ? "" : "s") · \(routines.count) routine" +
                (routines.count == 1 ? "" : "s"),
            at: CGPoint(x: margin, y: y), font: subtitleFont, color: .darkGray
        )
        y += 40
        let routineNames = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0.name) })
        let dayColumn = width * 0.4
        for (index, routineID) in program.routineIDs.enumerated() {
            let name = routineNames[routineID] ?? "—"
            draw("Day \(index + 1)", at: CGPoint(x: margin, y: y), font: bodyFont, color: .black)
            draw(name, at: CGPoint(x: margin + dayColumn, y: y), font: bodyFont, color: .black)
            y += rowHeight
        }
        y += 12
        drawWeekGrid(program.programWeeks, at: CGPoint(x: margin, y: y), width: width)
    }

    private static func drawWeekGrid(_ weeks: [PlanProgramWeek], at origin: CGPoint, width: CGFloat) {
        let sorted = weeks.sorted { $0.index < $1.index }
        let columnWidth = width / CGFloat(max(sorted.count, 1))
        for (offset, week) in sorted.enumerated() {
            let x = origin.x + CGFloat(offset) * columnWidth
            draw("W\(week.index)", at: CGPoint(x: x, y: origin.y), font: headerFont, color: .darkGray)
            draw(week.kind.capitalized, at: CGPoint(x: x, y: origin.y + 18), font: bodyFont, color: .black)
        }
    }

    // MARK: - Drawing primitives

    private static func drawRow(
        _ cells: [String], at origin: CGPoint, width: CGFloat, font: UIFont, color: UIColor
    ) {
        var x = origin.x
        for (index, cell) in cells.enumerated() where index < columnWidths.count {
            let columnWidth = width * columnWidths[index]
            draw(cell, at: CGPoint(x: x, y: origin.y), font: font, color: color, maxWidth: columnWidth - 6)
            x += columnWidth
        }
    }

    private static func draw(
        _ text: String, at point: CGPoint, font: UIFont, color: UIColor, maxWidth: CGFloat? = nil
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = CGRect(x: point.x, y: point.y, width: maxWidth ?? 500, height: rowHeight)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func drawLine(from start: CGPoint, to end: CGPoint) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// A short vertical bracket to the left of a superset's rows.
    private static func drawSupersetMarker(at point: CGPoint, height: CGFloat) {
        let path = UIBezierPath()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x, y: point.y + height * 0.8))
        UIColor.systemOrange.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    // MARK: - Fonts

    private static var titleFont: UIFont {
        UIFont(name: DGFont.Family.condensedBold, size: 26) ?? .boldSystemFont(ofSize: 26)
    }

    private static var subtitleFont: UIFont {
        UIFont(name: DGFont.Family.medium, size: 12) ?? .systemFont(ofSize: 12)
    }

    private static var headerFont: UIFont {
        UIFont(name: DGFont.Family.semiBold, size: 10) ?? .boldSystemFont(ofSize: 10)
    }

    private static var bodyFont: UIFont {
        UIFont(name: DGFont.Family.regular, size: 11) ?? .systemFont(ofSize: 11)
    }
}
