import SwiftUI

/// `BodyView`'s Apple Health body-composition card (body fat %, lean mass, height) plus the
/// "turn on in Settings" discovery line shared with the section-hidden state — split out of
/// `BodyView.swift` to stay under the type-body-length lint limit. Relies on members `BodyView`
/// deliberately left non-`private` (`preferences`, `healthInsights`, `composition`,
/// `isShowingHealthSettings`, `displayWeight`) since `private` is file-scoped and this is a
/// separate file.
extension BodyView {
    @ViewBuilder
    var bodyCompositionCard: some View {
        if let composition {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                Text("Body Composition").dgLabel()
                Text("From Apple Health.").font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                HStack(spacing: DGSpace.s2) {
                    if let bodyFat = composition.bodyFat {
                        compositionTile(
                            value: "\(Int(bodyFat.value.rounded()))%",
                            label: "Body Fat", date: bodyFat.date
                        )
                    }
                    if let leanMass = composition.leanMass {
                        compositionTile(
                            value: preferences.formatWeight(kg: leanMass.value),
                            label: "Lean Mass", date: leanMass.date
                        )
                    }
                    if let height = composition.height {
                        compositionTile(
                            value: heightLabel(meters: height.value), label: "Height", date: height.date
                        )
                    }
                }
                compositionTrend(composition)
            }
            .dgCard()
        } else if !preferences.healthReadBodyComposition, healthInsights.isAvailable {
            healthDiscoveryLine
        }
    }

    private func compositionTile(value: String, label: String, date: Date) -> some View {
        StatTile(value: value, label: label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) \(value), measured \(Self.longDateLabel(date))")
    }

    /// Body fat history takes priority over lean-mass history when both exist — one small chart
    /// keeps the card from getting crowded, and body fat % is the more commonly tracked figure.
    @ViewBuilder
    private func compositionTrend(_ composition: HealthInsightsService.BodyComposition) -> some View {
        if composition.bodyFatHistory.count > 1 {
            TrendChartView(
                points: composition.bodyFatHistory.map { .init(date: $0.date, value: $0.value) },
                lineColor: DGColor.infoText, height: 90
            )
        } else if composition.leanMassHistory.count > 1 {
            TrendChartView(
                points: composition.leanMassHistory.map {
                    .init(date: $0.date, value: displayWeight($0.value))
                },
                lineColor: DGColor.infoText, height: 90
            )
        }
    }

    /// Metric height in cm for the kg unit, imperial feet/inches for the lb unit — matching
    /// whichever system `preferences.weightUnit` already implies.
    private func heightLabel(meters: Double) -> String {
        switch preferences.weightUnit {
        case .kg:
            return "\(Int((meters * 100).rounded())) cm"
        case .lb:
            let totalInches = meters * 39.3701
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
            return "\(feet)'\(inches)\""
        }
    }

    /// A quiet, single-line pointer to Settings › Apple Health, shown wherever a Health-backed
    /// section is hidden because its preference is off — never a nag, just discoverable.
    var healthDiscoveryLine: some View {
        Button { isShowingHealthSettings = true } label: {
            Text("Turn on in Settings \u{203A} Apple Health")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .buttonStyle(.plain)
    }

    private static func longDateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
