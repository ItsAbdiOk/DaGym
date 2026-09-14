import SwiftUI

/// `RecoveryMapView`'s Apple Health context card — resting heart rate, HRV and last night's
/// sleep, shown alongside the muscle recovery map as plain information, never a readiness score
/// or a training recommendation. Split out of `RecoveryMapView.swift` to stay under the
/// type-body-length lint limit; relies on members that file deliberately left non-`private`
/// (`preferences`, `healthInsights`, `recoverySignals`, `isShowingHealthSettings`) since
/// `private` is file-scoped and this is a separate file.
extension RecoveryMapView {
    @ViewBuilder
    var healthContextCard: some View {
        if let recoverySignals {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                Text("Health").dgLabel()
                VStack(spacing: DGSpace.s2) {
                    if let rhr = recoverySignals.restingHeartRate {
                        let average = recoverySignals.restingHeartRateAverage30Day
                        healthRow(
                            title: "Resting Heart Rate", value: "\(Int(rhr.value.rounded())) bpm",
                            date: rhr.date, trend: trendText(current: rhr.value, average: average)
                        )
                    }
                    if let hrv = recoverySignals.hrv {
                        let average = recoverySignals.hrvAverage30Day
                        healthRow(
                            title: "Heart Rate Variability", value: "\(Int(hrv.value.rounded())) ms",
                            date: hrv.date, trend: trendText(current: hrv.value, average: average)
                        )
                    }
                    if let sleep = recoverySignals.sleep {
                        healthRow(
                            title: "Last Night's Sleep", value: Self.sleepLabel(sleep), date: sleep.end,
                            trend: nil
                        )
                    }
                }
                Text("Context only — not a readiness score.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            }
            .dgCard()
        } else if healthInsights.shouldOfferPermissionCheck(
            toggleOn: preferences.healthReadRecovery, hasData: false
        ) {
            // Toggle on, HealthKit already asked, nothing back. A denied read is indistinguishable
            // from no data, so point at the one place the user can check.
            healthPermissionCheckLine
        } else if !preferences.healthReadRecovery, healthInsights.isAvailable {
            healthDiscoveryLine
        }
    }

    /// Same wording as the Body screen's: an empty Health card with its toggle on is almost
    /// always read access switched off in the Health app.
    var healthPermissionCheckLine: some View {
        Text(
            "Nothing from Apple Health yet \u{2014} check Health \u{203A} Sharing \u{203A} Apps."
        )
            .font(DGFont.footnote)
            .foregroundStyle(DGColor.ink4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func healthRow(title: String, value: String, date: Date, trend: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DGFont.body).foregroundStyle(DGColor.ink1)
                Text(Self.dateLabel(date)).font(DGFont.footnote).foregroundStyle(DGColor.ink4)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(DGFont.title3).foregroundStyle(DGColor.ink1)
                if let trend {
                    Text(trend).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
                }
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: DGTap.min)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(title: title, value: value, date: date, trend: trend))
    }

    private func rowAccessibilityLabel(title: String, value: String, date: Date, trend: String?) -> String {
        var label = "\(title): \(value), \(Self.dateLabel(date))"
        if let trend { label += ", \(trend)" }
        return label
    }

    /// Strictly descriptive: "up/down from your 30-day average", never a judgment call. Nil when
    /// there's no average to compare against, or the move is small enough to be noise.
    private func trendText(current: Double, average: Double?) -> String? {
        guard let average, average > 0 else { return nil }
        let deltaPercent = (current - average) / average * 100
        guard abs(deltaPercent) >= 3 else { return nil }
        return deltaPercent > 0 ? "up from your 30-day average" : "down from your 30-day average"
    }

    private static func sleepLabel(_ interval: HealthSleepInterval) -> String {
        let seconds = Int(interval.end.timeIntervalSince(interval.start))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// A quiet, single-line pointer to Settings › Apple Health, shown when this section is
    /// hidden because the toggle is off — never a nag, just discoverable.
    var healthDiscoveryLine: some View {
        Button { isShowingHealthSettings = true } label: {
            Text("Turn on in Settings \u{203A} Apple Health")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .buttonStyle(.plain)
    }
}
