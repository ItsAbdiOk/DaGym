import SwiftUI

/// Legal/attribution screen: renders `Resources/Acknowledgements.md` as
/// Markdown. Not wired into any navigation yet — standalone until the
/// Settings tab exists.
struct AcknowledgementsView: View {
    @State private var rendered = AttributedString(loadingText)

    private static let loadingText = "Loading acknowledgements…"
    private static let fallbackText =
        "Acknowledgements are unavailable right now. See docs/exercise-data-sources.md in the "
        + "project repository for full attribution details."

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    Text(rendered)
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dgCard()
                        .padding(DGSpace.s5)
                }
            }
            .navigationTitle("Acknowledgements")
            .task { rendered = Self.loadMarkdown() }
        }
    }

    private static func loadMarkdown() -> AttributedString {
        guard
            let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return AttributedString(fallbackText)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    AcknowledgementsView()
}
