import SwiftUI

/// Legal screen: renders `Resources/PrivacyPolicy.md` as Markdown.
struct PrivacyPolicyView: View {
    @State private var rendered: AttributedString = AttributedString(loadingText)

    private static let loadingText = "Loading privacy policy…"
    private static let fallbackText =
        "The privacy policy is unavailable right now. See DaGym/Resources/PrivacyPolicy.md in "
        + "the project repository."

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
            .navigationTitle("Privacy Policy")
            .task { rendered = Self.loadMarkdown() }
        }
    }

    static func loadMarkdown() -> AttributedString {
        guard
            let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return AttributedString(fallbackText)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    PrivacyPolicyView()
}
