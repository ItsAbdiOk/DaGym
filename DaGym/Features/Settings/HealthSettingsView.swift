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
                    DGIconButton(symbol: "xmark") { dismiss() }
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
                        + "both ways, and a logged entry here is sent to Health too.",
                    isOn: binding(\.healthSyncBodyweight)
                )
            }
            .dgCard(padding: 0)
        }
    }

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
