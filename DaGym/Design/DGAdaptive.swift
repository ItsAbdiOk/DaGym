import SwiftUI

/// Dynamic Type layout helpers. Two tools cover nearly every screen:
///
/// - `DGAdaptiveStack`: an `HStack` at regular sizes that becomes a leading-aligned `VStack`
///   once the user is on an accessibility size, so a header row (title · buttons), a pair of
///   half-width cards or a strip of stat tiles stacks instead of squeezing to a column of
///   mid-word wraps.
/// - `.dgDenseType()`: caps a genuinely dense control — a set row, the keypad, the rest pill —
///   at `.accessibility2`. Its numbers still grow ~1.4×, but a row that has to hold five
///   controls side by side stays a row. Prose is never capped.
struct DGAdaptiveStack<Content: View>: View {
    private let horizontalAlignment: HorizontalAlignment
    private let verticalAlignment: VerticalAlignment
    private let spacing: CGFloat?
    private let threshold: DynamicTypeSize
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter threshold: stack from this size up. Default: any accessibility size.
    init(
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .center,
        spacing: CGFloat? = DGSpace.s3,
        threshold: DynamicTypeSize = .accessibility1,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.threshold = threshold
        self.content = content()
    }

    var body: some View {
        if dynamicTypeSize >= threshold {
            VStackLayout(alignment: horizontalAlignment, spacing: spacing) { content }
                // A `Spacer()` that pushed siblings apart sideways would otherwise open a
                // tall gap; at the ideal height it collapses to nothing.
                .fixedSize(horizontal: false, vertical: true)
                // The row keeps the width it had as an `HStack`, so a parent `.frame` can't
                // centre it, and the children line up on the leading edge.
                .frame(
                    maxWidth: .infinity,
                    alignment: Alignment(horizontal: horizontalAlignment, vertical: .center)
                )
        } else {
            HStackLayout(alignment: verticalAlignment, spacing: spacing) { content }
        }
    }
}

/// `columns` across normally; half as many (at least two) at accessibility sizes. For strips of
/// stat tiles whose numbers would otherwise squeeze to one digit per line.
struct DGAdaptiveGrid<Content: View>: View {
    private let columns: Int
    private let spacing: CGFloat
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(columns: Int, spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let count = dynamicTypeSize.isAccessibilitySize ? max(2, columns / 2) : columns
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: count),
            spacing: spacing
        ) {
            content
        }
    }
}

extension View {
    /// Caps Dynamic Type at `.accessibility2` for a control whose layout cannot stack: set rows,
    /// the weight keypad, the rest pill, the workout action bar. Never use on prose.
    func dgDenseType() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension DynamicTypeSize {
    /// Shorthand for "stack instead of sitting side by side".
    var dgStacks: Bool { isAccessibilitySize }
}
