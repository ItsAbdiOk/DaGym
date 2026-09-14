import SwiftUI

/// Type scale from the design system. Barlow Condensed carries numbers and
/// titles; Barlow carries prose. All figures are tabular.
///
/// Dynamic Type: every font here scales, but on two curves. Prose (`body`, `subhead`,
/// `footnote`, `caption`, `title3`) rides the matching system text style, which more than
/// triples at the largest accessibility size — that is the text a low-vision lifter reads.
/// Display type (hero numbers, screen and card titles) and chrome (micro-labels, chips,
/// buttons, the tab bar) ride gentler curves — `.largeTitle` grows 1.8×, `.title3` 2.2× —
/// because a 48 pt number or an uppercase tracked label at 3× no longer fits any row it lives
/// in, and the system's own chrome (tab bars, nav buttons) scales the same restrained way.
enum DGFont {
    enum Family {
        static let condensedSemiBold = "BarlowCondensed-SemiBold"
        static let condensedBold = "BarlowCondensed-Bold"
        static let condensedExtraBold = "BarlowCondensed-ExtraBold"
        static let regular = "Barlow-Regular"
        static let medium = "Barlow-Medium"
        static let semiBold = "Barlow-SemiBold"
        static let bold = "Barlow-Bold"
    }

    /// 48/48 · 800 · −3 % — hero numbers.
    static let metricXL = Font.custom(Family.condensedExtraBold, size: 48, relativeTo: .largeTitle)
    /// 34/36 · 800 · −2 % — timer, elapsed.
    static let metricL = Font.custom(Family.condensedExtraBold, size: 34, relativeTo: .largeTitle)
    /// 24/26 · 700 — set-row weight and reps.
    static let metricM = Font.custom(Family.condensedBold, size: 24, relativeTo: .largeTitle)
    /// 28/34 · 700 — screen title.
    static let title1 = Font.custom(Family.condensedBold, size: 28, relativeTo: .largeTitle)
    /// 22/28 · 700 — card title.
    static let title2 = Font.custom(Family.condensedBold, size: 22, relativeTo: .largeTitle)
    /// 17/22 · 600 — row title.
    static let title3 = Font.custom(Family.condensedSemiBold, size: 17, relativeTo: .headline)
    /// 16/22 · 500 — prose.
    static let body = Font.custom(Family.medium, size: 16, relativeTo: .body)
    /// 14/19 · 500.
    static let subhead = Font.custom(Family.medium, size: 14, relativeTo: .subheadline)
    /// 13/17 · 500.
    static let footnote = Font.custom(Family.medium, size: 13, relativeTo: .footnote)
    /// 11/14 · 600.
    static let caption = Font.custom(Family.semiBold, size: 11, relativeTo: .caption)
    /// Barlow Condensed 12/12 · +12 % tracking, uppercase — micro labels.
    static let label = Font.custom(Family.condensedBold, size: 12, relativeTo: .title3)
    /// 10 pt condensed — tab bar labels.
    static let tabLabel = Font.custom(Family.condensedBold, size: 10, relativeTo: .largeTitle)
}

extension View {
    /// Uppercase condensed micro-label with the +12 % tracking from the spec.
    func dgLabel(_ color: Color = DGColor.ink3) -> some View {
        font(DGFont.label)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Tabular, tightly tracked hero/metric number.
    func dgMetric(_ font: Font, tracking: CGFloat = -1) -> some View {
        self.font(font)
            .monospacedDigit()
            .tracking(tracking)
    }
}
