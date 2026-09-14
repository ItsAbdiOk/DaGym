import SwiftUI

/// The "APPLE HEALTH" settings screen (plan.md §6.8): connect, then two plain-language toggles
/// for exactly what's shared. Presented as a sheet from `SettingsView`'s "Apple Health" row.
struct HealthSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(HealthSyncService.self) private var healthSync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s6) {
                        statusCard
                        toggleCard
                        permissionsCard
                        syncFooter
                        disclaimer
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s8)
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DGIconButton(symbol: "xmark", accessibilityLabel: "Close") { dismiss() }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DGColor.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(healthSync.isAvailable ? "Health is available" : "Health isn't available")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                    Text(statusSubtitle).font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                }
                Spacer()
            }
            if healthSync.isAvailable {
                DGPrimaryButton(
                    title: healthSync.isAuthorizing ? "Connecting…" : "Connect", symbol: "link",
                    height: 44
                ) {
                    Task { await healthSync.authorize() }
                }
                .disabled(healthSync.isAuthorizing)
            }
        }
        .dgCard()
    }

    private var statusSubtitle: String {
        healthSync.isAvailable
            ? "Grant access, then choose exactly what DaGym reads and writes below."
            : "This device doesn't support the Health app."
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("What's shared").dgLabel()
            VStack(spacing: 0) {
                HealthToggleRow(
                    title: "Save workouts to Health",
                    detail: "Each finished session is written as a strength-training workout with "
                        + "duration, sets and volume. No calorie estimate — we don't guess.",
                    isOn: binding(\.healthWriteWorkouts)
                )
                HealthDivider()
                HealthToggleRow(
                    title: "Sync bodyweight",
                    detail: "Health becomes the source of truth for your bodyweight: readings sync "
                        + "both ways, full history included, and a logged entry here is sent to "
                        + "Health too.",
                    isOn: binding(\.healthSyncBodyweight)
                )
                HealthDivider()
                HealthToggleRow(
                    title: "Read body composition",
                    detail: "Body fat percentage, lean body mass and height fill in Body screen "
                        + "fields automatically when Health has them. Read-only — never written.",
                    isOn: binding(\.healthReadBodyComposition)
                )
                HealthDivider()
                HealthToggleRow(
                    title: "Read recovery context",
                    detail: "Resting heart rate, heart-rate variability and last night's sleep show up "
                        + "as plain context next to the muscle recovery map. Read-only, and never a "
                        + "readiness score or training recommendation.",
                    isOn: binding(\.healthReadRecovery)
                )
                HealthDivider()
                HealthToggleRow(
                    title: "Import workouts from other apps",
                    detail: "Strength workouts logged on your Watch or in another app show up in "
                        + "History too. Never duplicated, and never anything DaGym itself wrote.",
                    isOn: binding(\.healthImportWorkouts)
                )
                HealthDivider()
                HealthToggleRow(
                    title: "Estimate calories",
                    detail: "Off by default: we don't guess. Turning this on adds a rough "
                        + "active-energy estimate to each saved workout, clearly marked in Health "
                        + "as an estimate rather than a real heart-rate reading.",
                    isOn: binding(\.healthEstimateCalories)
                )
            }
            .dgCard(padding: 0)
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Exactly what's read and written").dgLabel()
            VStack(spacing: 0) {
                ForEach(Array(Self.permissionRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { HealthDivider() }
                    HealthPermissionRow(row: row)
                }
            }
            .dgCard(padding: 0)
        }
    }

    /// The complete list `requestAuthorization()` grants, one row per data type, in plain
    /// language — so nothing DaGym can read or write to Health is a surprise. Kept in sync by
    /// hand with `HealthKitStore.readTypes`/`writeTypes`.
    private static let permissionRows: [HealthPermissionRow.Info] = [
        .init(
            kind: .read, title: "Bodyweight", reason: "Backs the bodyweight chart and trend logic."
        ),
        .init(
            kind: .read, title: "Body fat %, lean mass, height",
            reason: "Fills in Body screen fields when \"Read body composition\" is on."
        ),
        .init(
            kind: .read, title: "Heart-rate variability, resting heart rate, sleep",
            reason: "Shown as context on the Recovery map — never a readiness score."
        ),
        .init(
            kind: .read, title: "Workouts from other apps",
            reason: "Surfaced in History when \"Import workouts from other apps\" is on."
        ),
        .init(
            kind: .write, title: "Bodyweight", reason: "Two-way sync when \"Sync bodyweight\" is on."
        ),
        .init(
            kind: .write, title: "Strength workouts",
            reason: "Every finished session, when \"Save workouts to Health\" is on."
        ),
        .init(
            kind: .write, title: "Active energy (calories)",
            reason: "Only when \"Estimate calories\" is on, clearly marked as an estimate."
        )
    ]

    @ViewBuilder
    private var syncFooter: some View {
        if let lastSync = healthSync.lastSyncDate {
            Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var disclaimer: some View {
        Text("Training suggestions, not medical advice.")
            .font(DGFont.footnote)
            .foregroundStyle(DGColor.ink4)
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }
}

/// One toggle row with a title and a plain-language explanation underneath.
private struct HealthToggleRow: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DGFont.body).foregroundStyle(DGColor.ink1)
                Text(detail)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DGSpace.s3)
            Toggle("", isOn: $isOn).tint(DGColor.coral).labelsHidden()
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s4)
    }
}

private struct HealthDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

/// One row of the "Exactly what's read and written" list: a Read/Write badge, the data type,
/// and why DaGym touches it.
private struct HealthPermissionRow: View {
    struct Info {
        enum Kind { case read, write }
        var kind: Kind
        var title: String
        var reason: String
    }

    var row: Info

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            Text(row.kind == .read ? "READ" : "WRITE")
                .font(DGFont.condensedLabel(11))
                .foregroundStyle(row.kind == .read ? DGColor.ink3 : DGColor.coral)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(DGFont.body).foregroundStyle(DGColor.ink1)
                Text(row.reason).font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s4)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            HealthSettingsView()
                .environment(preferences)
                .environment(store)
                .environment(HealthSyncService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(EmptyView())
}
