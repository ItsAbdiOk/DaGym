import GymCore
import SwiftUI

/// Screen 8: four rows, no sub-screens. Units, Haptics, Voice log, and the sync row. Sets
/// logged offline sit in the local store until CloudKit pushes them; the count is what is
/// still unsent, best-effort from the last save time.
struct SettingsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        ScrollView {
            VStack(spacing: 6) {
                SafeBandText(text: "Settings", font: WatchFont.title, color: WatchColor.ink)
                row("Units") {
                    HStack(spacing: 0) {
                        unitChoice(.kg)
                        unitChoice(.lb)
                    }
                    .background(Capsule().fill(WatchColor.cardRaised))
                }
                row("Haptics") { Toggle("Haptics", isOn: $preferences.haptics).labelsHidden() }
                row("Voice log") { Toggle("Voice log", isOn: $preferences.voiceLog).labelsHidden() }
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone synced").font(WatchFont.bodyMedium).foregroundStyle(WatchColor.ink)
                    Text(syncLine).font(WatchFont.secondary).foregroundStyle(WatchColor.inkSecondary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: WatchMetric.listRow, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: WatchMetric.cardRadius).fill(WatchColor.card))
            }
            .padding(.horizontal, WatchMetric.gutter)
        }
    }

    /// One half of the kg / lb pill.
    private func unitChoice(_ unit: WeightUnit) -> some View {
        let selected = preferences.weightUnit == unit
        return Button(unit.symbol) { preferences.weightUnit = unit }
            .font(WatchFont.bodyMedium)
            .foregroundStyle(selected ? Color.black : WatchColor.inkSecondary)
            .frame(width: WatchMetric.isSmall ? 34 : 40, height: 28)
            .background(Capsule().fill(selected ? WatchColor.accent : .clear))
            .buttonStyle(.plain)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(WatchFont.bodyMedium).foregroundStyle(WatchColor.ink).lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: WatchMetric.listRow)
        .background(RoundedRectangle(cornerRadius: WatchMetric.cardRadius).fill(WatchColor.card))
    }

    /// CloudKit mirroring does not expose its outbound queue, so "queued" counts the workouts
    /// still open on this watch — the only rows guaranteed not to be on the phone yet. The
    /// count comes from `refreshHome` rather than a fetch in the body, which re-ran on every
    /// toggle flip. "iCloud off" says the store opened local-only (see `WatchRoot`).
    private var syncLine: String {
        let queued = store.home.unfinishedCount
        let when = preferences.lastSavedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "never"
        let line = queued == 0 ? "\(when) · nothing queued" : "\(when) · \(queued) in progress"
        return store.isCloudSyncOn ? line : "iCloud off · \(line)"
    }
}
