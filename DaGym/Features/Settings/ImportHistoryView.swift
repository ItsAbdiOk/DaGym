import SwiftUI

/// Settings › Data & backup › Import history: every import that has landed on this device,
/// newest first — "Strong · 42 workouts, 380 sets" over the date it landed. Read-only; the log
/// itself is `ImportHistoryLog`, local to the device.
struct ImportHistoryView: View {
    var log: ImportHistoryLog = .shared
    @State private var entries: [ImportHistoryEntry] = []

    var body: some View {
        SettingsPage(title: "Import history") {
            if entries.isEmpty {
                SettingsNote(
                    text: "Nothing imported yet. Backups, Strong, Hevy and FitNotes files and Apple "
                        + "Health workouts you pull in will be listed here."
                )
            } else {
                SettingsSection {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                        ImportHistoryRow(entry: entry)
                        if offset < entries.count - 1 { SettingsDivider() }
                    }
                }
                .accessibilityIdentifier(A11yID.importHistoryList)
                SettingsNote(text: "Kept on this device only; the last \(ImportHistoryLog.capacity) imports.")
            }
        }
        .onAppear { entries = log.entries() }
    }
}

/// "Strong · 42 workouts, 380 sets" over the date it landed, with a warning glyph when the
/// import reported problems.
struct ImportHistoryRow: View {
    var entry: ImportHistoryEntry

    var body: some View {
        SettingsRow(
            label: "\(entry.source) · \(entry.summary)", sub: Self.dateFormatter.string(from: entry.date)
        ) {
            if entry.problems > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.warning)
                    .accessibilityLabel("\(entry.problems) problems")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    let log = ImportHistoryLog.scratch()
    log.record(.health(workouts: 3))
    log.record(ImportHistoryEntry(
        date: Date().addingTimeInterval(-86_400), source: "Strong",
        counts: [.init(label: "workout", value: 42), .init(label: "set", value: 380)], problems: 1
    ))
    return NavigationStack { ImportHistoryView(log: log) }
}
