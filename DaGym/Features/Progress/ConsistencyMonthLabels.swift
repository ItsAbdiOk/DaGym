import Foundation
import GymCore

/// Which week-columns of the consistency heatmap carry a month name, by column index. Pure, so
/// the placement rules are tested without laying the grid out.
enum ConsistencyMonthLabels {
    /// A label is about three columns wide (10 pt squares, 3 pt gaps, "MAR" tracked out), so two
    /// labels closer than this overlap and the first one is dropped.
    static let minimumColumnsBetweenLabels = 3

    /// One label per week-column whose first real day starts a new month. The very first column
    /// is labelled too — a grid that opens on 15 Sep still says which September that is — unless
    /// the next month starts within `minimumColumnsBetweenLabels`, in which case the opening
    /// month gives way to the one that owns the room.
    static func labels(for grid: [[DayCell?]], calendar: Calendar) -> [Int: String] {
        var placed: [(column: Int, label: String)] = []
        var lastMonth: Int?
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM"
        for (index, week) in grid.enumerated() {
            guard let cell = week.compactMap({ $0 }).first else { continue }
            let month = calendar.component(.month, from: cell.date)
            if month != lastMonth {
                placed.append((index, formatter.string(from: cell.date).uppercased()))
                lastMonth = month
            }
        }
        var labels: [Int: String] = [:]
        for (offset, entry) in placed.enumerated() {
            if let next = placed.dropFirst(offset + 1).first,
               next.column - entry.column < minimumColumnsBetweenLabels {
                continue
            }
            labels[entry.column] = entry.label
        }
        return labels
    }
}
