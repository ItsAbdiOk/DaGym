import SwiftUI

/// `RecoveryMapView`'s "Apple Health context" card — resting heart rate, HRV and last night's
/// sleep as three tiles, shown alongside the recovery map as plain information, never a
/// readiness score or a training recommendation. Split out of `RecoveryMapView.swift` to stay
/// under the type-body-length lint limit; relies on members that file deliberately left
/// non-`private` (`preferences`, `healthInsights`, `recoverySignals`, `isShowingHealthSettings`)
/// since `private` is file-scoped and this is a separate file.
extension RecoveryMapView {
    @ViewBuilder
    var healthContextCard: some View {
        if let recoverySignals {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                ProgressCardTitle(title: "Apple Health context")
                HStack(spacing: DGSpace.s2) {
                    if let rhr = recoverySignals.restingHeartRate {
                        let average = recoverySignals.restingHeartRateAverage30Day
                        healthTile(
                            value: "\(Int(rhr.value.rounded()))", label: "Resting HR", date: rhr.date,
                            trend: trendText(current: rhr.value, average: average)
                        )
                    }
                    if let hrv = recoverySignals.hrv {
                        healthTile(
                            value: "\(Int(hrv.value.rounded())) ms", label: "HRV", date: hrv.date,
                            trend: trendText(current: hrv.value, average: recoverySignals.hrvAverage30Day)
                        )
                    }
                    if let sleep = recoverySignals.sleep {
                        healthTile(
                            value: Self.sleepLabel(sleep), label: "Last night", date: sleep.end, trend: nil
                        )
                    }
                }
                Text("Context only, not advice.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dgCard(radius: 20, padding: DGSpace.s4)
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

    /// "52 / Resting HR" on a low ink wash; the date and 30-day trend go to VoiceOver only.
    /// Each tile is a door to the Health settings that decide what is read.
    private func healthTile(value: String, label: String, date: Date, trend: String?) -> some View {
        Button { isShowingHealthSettings = true } label: {
            VStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                DGColor.ink1.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.dgCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tileAccessibilityLabel(label: label, value: value, date: date, trend: trend))
        .accessibilityHint("Opens Apple Health settings")
    }

    private func tileAccessibilityLabel(label: String, value: String, date: Date, trend: String?) -> String {
        var text = "\(label): \(value), \(Self.dateLabel(date))"
        if let trend { text += ", \(trend)" }
        return text
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
                .frame(minHeight: DGTap.min)
        }
        .buttonStyle(.dgControl)
    }
}
