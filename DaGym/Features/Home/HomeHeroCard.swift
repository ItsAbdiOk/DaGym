import GymCore
import SwiftUI

/// Today's hero card from the redesign: a status pill, the routine (or what's next on a rest
/// day), the muscles it hits beside a body-map thumbnail, and one accent "Start" button with a
/// "…" beside it for the other ways to start (`StartSomethingElseSheet`).
struct HomeHeroCard: View {
    enum Variant {
        /// `isScheduled` false = no weekly plan yet, so the routine is a suggestion, not a booking.
        case scheduled(routine: RoutineInfo, isScheduled: Bool)
        case rest(nextSessionText: String?)
    }

    var variant: Variant
    var onPrimary: () -> Void
    var onMore: () -> Void
    /// The title and meta line: the routine itself (the builder) when one is scheduled, the
    /// Schedule segment on a rest day — "Next: Pull B · Thursday" is a door to the week plan.
    var onTitle: () -> Void
    /// "Week 3 of 8" beside the pill: the program that says so.
    var onWeekLabel: () -> Void
    /// The "HITS" muscles and the thumbnail: the muscle map.
    var onHits: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DGSpace.s2) {
                HomeStatusPill(text: pillText)
                if let weekLabel {
                    Button(action: onWeekLabel) {
                        HStack(spacing: 3) {
                            Text(weekLabel)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(DGColor.ink3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DGColor.ink1.opacity(0.3))
                        }
                    }
                    .buttonStyle(.dgControl)
                    .accessibilityHint("Opens Programs")
                }
            }
            Button(action: onTitle) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: DGSpace.s2) {
                        Text(title)
                            .font(.system(size: 25, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(DGColor.ink1)
                            .multilineTextAlignment(.leading)
                        HomeChevron()
                    }
                    .padding(.top, 14)
                    Text(meta)
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(DGColor.ink3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dgRow)
            .accessibilityHint(titleHint)
            .accessibilityIdentifier(A11yID.homeHeroTitle)
            if case .scheduled(let routine, _) = variant {
                hits(routine)
            }
            HStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: DGColor.coral.opacity(0.3), radius: 10, y: 8)
                }
                .buttonStyle(DGPressStyle())
                .accessibilityIdentifier(A11yID.homeStart)
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DGColor.ink3)
                        .frame(width: 52, height: 50)
                        .homeSecondaryFill()
                }
                .buttonStyle(DGPressStyle())
                .accessibilityLabel("More ways to start")
                .accessibilityIdentifier(A11yID.homeStartMore)
            }
            .padding(.top, 18)
        }
        .dgCard(radius: DGRadius.xl)
    }

    /// "HITS" kicker, the named muscles and the thumbnail, under a hairline. The whole strip
    /// is one door to the muscle map — the words and the figure say the same thing.
    private func hits(_ routine: RoutineInfo) -> some View {
        let lines = HomeHits.lines(summary: routine.hitSummary)
        return Button(action: onHits) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DGSpace.s2) {
                    Text("Hits").dgLabel()
                    Text(lines.named)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(DGColor.ink1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let light = lines.light {
                        Text(light)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DGColor.ink3)
                    }
                }
                Spacer(minLength: DGSpace.s3)
                BodyMapPair(intensity: routine.hitMap, height: 60)
                HomeChevron()
            }
            .padding(.top, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the muscle map")
        .accessibilityIdentifier(A11yID.homeHits)
        .overlay(alignment: .top) { Rectangle().fill(DGColor.hairline).frame(height: 0.5) }
        .padding(.top, 16)
    }

    // MARK: Copy

    private var titleHint: String {
        switch variant {
        case .scheduled: "Opens the routine"
        case .rest: "Opens the schedule"
        }
    }

    private var pillText: String {
        switch variant {
        case .scheduled(_, let isScheduled): isScheduled ? "Scheduled" : "Suggested"
        case .rest: HomeSnapshot.restDayHeadline
        }
    }

    private var weekLabel: String? {
        guard case .scheduled(let routine, _) = variant, let label = routine.weekLabel, !label.isEmpty else {
            return nil
        }
        return label
    }

    private var title: String {
        switch variant {
        case .scheduled(let routine, _): routine.name
        case .rest(let nextSessionText): nextSessionText ?? "Nothing scheduled"
        }
    }

    private var meta: String {
        switch variant {
        case .scheduled(let routine, _):
            "\(routine.exercises.count) exercises · \(routine.setCount) sets"
                + " · ~\(routine.estimatedMinutes) min"
        case .rest:
            "No routine scheduled today. Start a freestyle workout whenever you're ready."
        }
    }

    private var primaryTitle: String {
        switch variant {
        case .scheduled: "Start workout"
        case .rest: "Freestyle workout"
        }
    }
}

extension View {
    /// The quiet grey square/pill beside a hero card's accent button ("…", "Ask the coach").
    func homeSecondaryFill() -> some View {
        background(DGColor.ink1.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DGColor.ink1.opacity(0.1), lineWidth: 0.5)
            }
    }
}

/// The accent pill above a hero title ("SCHEDULED", "REST DAY", "GET STARTED").
struct HomeStatusPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.inkOnCoral)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DGColor.coral, in: Capsule())
    }
}

/// Turns `RoutineInfo.hitSummary` ("Chest, front delts, triceps · light on back") into the
/// hero card's two lines: the named muscles dotted together, title-cased, and the light
/// clause on its own. Pure so the wording is testable without a view.
enum HomeHits {
    static let lightMarker = " · light on "

    static func lines(summary: String) -> (named: String, light: String?) {
        let parts = summary.components(separatedBy: lightMarker)
        let named = parts[0]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " · ")
        let light = parts.count > 1 ? "Light on \(parts[1])" : nil
        // A routine that is only "light on" something has its clause as the first part already.
        if named.lowercased().hasPrefix("light on ") { return (named, nil) }
        return (named, light)
    }
}

#Preview {
    VStack(spacing: DGSpace.s3) {
        HomeHeroCard(
            variant: .scheduled(routine: SampleData.pushA, isScheduled: true),
            onPrimary: {}, onMore: {}, onTitle: {}, onWeekLabel: {}, onHits: {}
        )
        HomeHeroCard(
            variant: .rest(nextSessionText: "Next: Pull B · Thursday"),
            onPrimary: {}, onMore: {}, onTitle: {}, onWeekLabel: {}, onHits: {}
        )
    }
    .padding()
    .background(AmbientWash())
}
