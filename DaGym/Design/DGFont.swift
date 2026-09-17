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
    /// Kept for the share card and any custom-size caller; the app's own type is SF system
    /// (the redesign prototype is set entirely in `-apple-system`). Barlow stays bundled so the
    /// exported story card keeps its display face.
    enum Family {
        static let condensedSemiBold = "BarlowCondensed-SemiBold"
        static let condensedBold = "BarlowCondensed-Bold"
        static let condensedExtraBold = "BarlowCondensed-ExtraBold"
        static let regular = "Barlow-Regular"
        static let medium = "Barlow-Medium"
        static let semiBold = "Barlow-SemiBold"
        static let bold = "Barlow-Bold"
    }

    // Metrics: bold SF with tabular digits (`dgMetric` adds `monospacedDigit`).
    static let metricXL = Font.system(size: 44, weight: .bold)
    static let metricL = Font.system(.largeTitle, design: .default, weight: .bold)
    static let metricM = Font.system(.title2, design: .default, weight: .bold)
    /// 33 pt / 700 — the tab screens' large title ("Today", "Train", "You").
    static let title1 = Font.system(.largeTitle, design: .default, weight: .bold)
    /// 25 pt / 700 — the hero card title ("Push · Heavy").
    static let title2 = Font.system(.title2, design: .default, weight: .bold)
    /// 17 pt / 600 — row and card headings.
    static let title3 = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let subhead = Font.system(.subheadline, design: .default, weight: .regular)
    static let footnote = Font.system(.footnote, design: .default, weight: .regular)
    static let caption = Font.system(.caption, design: .default, weight: .semibold)
    /// 11 pt / 600, uppercase, tracked — section kickers ("THIS WEEK", "HITS").
    static let label = Font.system(.caption, design: .default, weight: .semibold)
    static let tabLabel = Font.system(.caption2, design: .default, weight: .semibold)
}

extension View {
    /// Uppercase condensed micro-label with the +12 % tracking from the spec.
    func dgLabel(_ color: Color = DGColor.ink3) -> some View {
        font(DGFont.label)
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Tabular, tightly tracked hero/metric number.
    func dgMetric(_ font: Font, tracking: CGFloat = -0.5) -> some View {
        self.font(font)
            .monospacedDigit()
            .tracking(tracking)
    }
}
