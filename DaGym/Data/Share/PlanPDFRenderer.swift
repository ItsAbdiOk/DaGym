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

/// Renders a clean, printable routine/program sheet from a `PlanDocument` (plan.md §6.8). A
/// routine export is one page per routine (title, exercise table with superset brackets). A
/// program export is a cover page (schedule, week strip, progression rules) plus one page per
/// week listing that week's routines and their planned sets — see `+Program.swift`. Every page
/// carries a "Page n of N" footer, and a routine or week that outgrows a page continues onto the
/// next. Pure UIKit (`UIGraphicsPDFRenderer`), no SwiftUI dependency, so it can run off the main
/// thread. Typography mirrors `DGFont`'s Barlow families.
enum PlanPDFRenderer {
    static let margin: CGFloat = 40
    static let rowHeight: CGFloat = 28
    /// Compact rows for the week pages, where three routines share one sheet.
    static let compactRowHeight: CGFloat = 22
    static let columnWidths: [CGFloat] = [0.34, 0.16, 0.18, 0.12, 0.20]

    static func render(
        _ document: PlanDocument, pageSize: PlanPDFPageSize = .a4, unit: WeightUnit = .kg
    ) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize.size)
        let pages = PlanPDFPages(bounds: bounds)
        if let program = document.program {
            layoutProgram(program, routines: document.routines, into: pages, unit: unit)
        } else {
            for routine in document.routines {
                pages.beginPage()
                layoutRoutine(routine, into: pages, unit: unit)
            }
        }
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            pages.draw(in: context)
        }
    }

    // MARK: - Routine page

    static func layoutRoutine(_ routine: PlanRoutine, into pages: PlanPDFPages, unit: WeightUnit) {
        let width = pages.contentWidth
        pages.add(height: 40) { y in
            draw(routine.name.uppercased(), at: CGPoint(x: margin, y: y), font: titleFont)
        }
        pages.add(height: 32) { y in
            draw(
                subtitle(for: routine, unit: unit), at: CGPoint(x: margin, y: y), font: subtitleFont,
                color: .darkGray
            )
        }
        layoutExerciseTable(routine, into: pages, width: width, rowHeight: rowHeight, unit: unit)
    }

    /// The header row plus one row per exercise, at `rowHeight`. Rows flow onto a new page when
    /// they run out of room, so a 12-exercise routine still prints in full.
    static func layoutExerciseTable(
        _ routine: PlanRoutine, into pages: PlanPDFPages, width: CGFloat, rowHeight: CGFloat,
        unit: WeightUnit
    ) {
        pages.add(height: rowHeight) { y in
            drawTableHeader(at: CGPoint(x: margin, y: y), width: width, rowHeight: rowHeight)
        }
        var lastGroup: Int?
        for exercise in routine.exercises.sorted(by: { $0.order < $1.order }) {
            let isSupersetStart = exercise.supersetGroup != nil && exercise.supersetGroup != lastGroup
            pages.add(height: rowHeight) { y in
                if isSupersetStart {
                    drawSupersetMarker(at: CGPoint(x: margin - 14, y: y), height: rowHeight)
                }
                drawExerciseRow(exercise, at: CGPoint(x: margin, y: y), width: width, unit: unit)
            }
            lastGroup = exercise.supersetGroup
        }
    }

    private static func subtitle(for routine: PlanRoutine, unit: WeightUnit) -> String {
        let count = routine.exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s") · \(ruleName(for: routine))"
    }

    /// The routine's rule by name; the stored raw key when the JSON is missing or unreadable.
    static func ruleName(for routine: PlanRoutine) -> String {
        ProgressionRuleCoding.decode(routine.ruleJSON)?.displayName ?? routine.progressionRule
    }

    private static func drawTableHeader(at origin: CGPoint, width: CGFloat, rowHeight: CGFloat) {
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

    static func setsRepsText(_ exercise: PlanRoutineExercise) -> String {
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

    static func targetText(_ exercise: PlanRoutineExercise, unit: WeightUnit) -> String {
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

    // MARK: - Drawing primitives

    static func drawRow(
        _ cells: [String], at origin: CGPoint, width: CGFloat, font: UIFont, color: UIColor
    ) {
        var x = origin.x
        for (index, cell) in cells.enumerated() where index < columnWidths.count {
            let columnWidth = width * columnWidths[index]
            draw(cell, at: CGPoint(x: x, y: origin.y), font: font, color: color, maxWidth: columnWidth - 6)
            x += columnWidth
        }
    }

    static func draw(
        _ text: String, at point: CGPoint, font: UIFont, color: UIColor = .black, maxWidth: CGFloat? = nil
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = CGRect(x: point.x, y: point.y, width: maxWidth ?? 500, height: rowHeight)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// Wrapped text: draws `text` inside `width` and returns nothing — pair with
    /// `paragraphHeight` to reserve the room first.
    static func drawParagraph(
        _ text: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let height = paragraphHeight(text, width: width, font: font)
        (text as NSString).draw(
            with: CGRect(x: point.x, y: point.y, width: width, height: height),
            options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
        )
    }

    static func paragraphHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil
        )
        return ceil(bounding.height) + 6
    }

    static func drawLine(from start: CGPoint, to end: CGPoint) {
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

    static var titleFont: UIFont {
        UIFont(name: DGFont.Family.condensedBold, size: 26) ?? .boldSystemFont(ofSize: 26)
    }

    static var sectionFont: UIFont {
        UIFont(name: DGFont.Family.condensedBold, size: 16) ?? .boldSystemFont(ofSize: 16)
    }

    static var subtitleFont: UIFont {
        UIFont(name: DGFont.Family.medium, size: 12) ?? .systemFont(ofSize: 12)
    }

    static var headerFont: UIFont {
        UIFont(name: DGFont.Family.semiBold, size: 10) ?? .boldSystemFont(ofSize: 10)
    }

    static var bodyFont: UIFont {
        UIFont(name: DGFont.Family.regular, size: 11) ?? .systemFont(ofSize: 11)
    }
}

/// Collects a document as pages of deferred draw commands, so the "Page n of N" footer knows N
/// before anything is drawn, and so a block that doesn't fit the page it's on moves to a fresh
/// one instead of running off the bottom.
final class PlanPDFPages {
    typealias Command = (CGFloat) -> Void

    let bounds: CGRect
    private let footerHeight: CGFloat = 24
    private var pages: [[(y: CGFloat, command: Command)]] = []
    private var y: CGFloat = 0
    /// Drawn at the top of any page the builder opens on its own (an overflow), so a
    /// continued week still says which week it is.
    var continuationHeader: ((PlanPDFPages) -> Void)?

    init(bounds: CGRect) {
        self.bounds = bounds
    }

    var contentWidth: CGFloat { bounds.width - PlanPDFRenderer.margin * 2 }
    var pageCount: Int { pages.count }
    private var bottom: CGFloat { bounds.height - PlanPDFRenderer.margin - footerHeight }

    func beginPage() {
        pages.append([])
        y = PlanPDFRenderer.margin
    }

    /// Reserves `height` on the current page — or the next one if it wouldn't fit — and queues
    /// `command` to draw at the reserved y.
    func add(height: CGFloat, _ command: @escaping Command) {
        if pages.isEmpty { beginPage() }
        if y + height > bottom {
            beginPage()
            continuationHeader?(self)
        }
        pages[pages.count - 1].append((y, command))
        y += height
    }

    func space(_ height: CGFloat) { y = min(y + height, bottom) }

    func draw(in context: UIGraphicsPDFRendererContext) {
        for (index, page) in pages.enumerated() {
            context.beginPage()
            for item in page { item.command(item.y) }
            let footer = "Page \(index + 1) of \(pages.count)"
            let font = PlanPDFRenderer.headerFont
            let width = (footer as NSString).size(withAttributes: [.font: font]).width
            PlanPDFRenderer.draw(
                footer, at: CGPoint(x: bounds.midX - width / 2, y: bounds.height - PlanPDFRenderer.margin),
                font: font, color: .gray
            )
        }
    }
}
