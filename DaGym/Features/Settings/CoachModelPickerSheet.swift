import SwiftUI

/// Which of the two chat models a picker or row is about: the coach that drafts, or the
/// second opinion that reviews each proposal (and can be off).
enum CoachModelRole: String, Identifiable, Sendable {
    case coach, reviewer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: "Coach"
        case .reviewer: "Second opinion"
        }
    }

    var canBeOff: Bool { self == .reviewer }
}

/// Picks one of the chat's models from OpenRouter's live list: searchable, tool-capable models
/// first (neither model can work without tools, so the rest are listed but marked), pricing
/// per million tokens from the API itself, the current choice ticked. The reviewer's picker
/// has an Off row on top. Saving writes `Preferences.coachModelID` or
/// `Preferences.coachReviewerModelID`; the current choice is kept even when the fetch fails.
struct CoachModelPickerSheet: View {
    var role: CoachModelRole = .coach

    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var models: [OpenRouterWire.Model] = []
    @State private var query = ""
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    private var filtered: [OpenRouterWire.Model] {
        CoachModelSearch.filter(models, query: query)
            .sorted { lhs, rhs in
                // Tool-capable first, then alphabetical by display name.
                if lhs.supportsTools != rhs.supportsTools { return lhs.supportsTools }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                content
            }
            .navigationTitle(role.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .searchable(text: $query, prompt: "Search models")
        }
        .presentationBackground(DGColor.surface1)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Fetching models…")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        case .failed(let reason):
            EmptyState(
                symbol: "wifi.exclamationmark", title: "Couldn't Load Models",
                message: "\(reason) Your current choice, \(currentName), is kept.",
                action: "Try Again", onAction: { Task { await load() } }
            )
            .padding(DGSpace.s6)
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("Prices are what OpenRouter reports for each model, per million tokens in and out.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DGSpace.s5)
                    .padding(.vertical, DGSpace.s3)
                if role.canBeOff {
                    offRow
                    CoachChatSettingsDivider()
                }
                ForEach(filtered) { model in
                    row(model)
                    CoachChatSettingsDivider()
                }
                if filtered.isEmpty {
                    Text("No models match \"\(query)\".")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                        .padding(DGSpace.s5)
                }
            }
            .dgCard(padding: 0)
            .padding(DGSpace.s4)
        }
        .accessibilityIdentifier(A11yID.coachModelSearch)
    }

    /// The saved id for this role; nil means the second opinion is off.
    private var selectedID: String? {
        switch role {
        case .coach: preferences.coachModelID
        case .reviewer: preferences.coachReviewerModelID
        }
    }

    private var currentName: String {
        selectedID.map(CoachChatConfiguration.displayName(forModelID:)) ?? "Off"
    }

    private func select(_ id: String?) {
        switch role {
        case .coach:
            if let id { preferences.coachModelID = id }
        case .reviewer:
            preferences.coachReviewerModelID = id
        }
    }

    private var offRow: some View {
        let isSelected = selectedID == nil
        return Button {
            select(nil)
        } label: {
            HStack(alignment: .top, spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Off").font(DGFont.body).foregroundStyle(DGColor.ink1)
                    Text("Proposals go straight to you, from the coach alone.")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DGSpace.s2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DGColor.coralText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .padding(.vertical, DGSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgControl)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("Off, no second opinion")
        .accessibilityIdentifier(A11yID.coachModelOff)
    }

    private func row(_ model: OpenRouterWire.Model) -> some View {
        let isSelected = model.id == selectedID
        return Button {
            select(model.id)
        } label: {
            HStack(alignment: .top, spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(DGFont.body).foregroundStyle(DGColor.ink1)
                    Text(model.id).font(DGFont.footnote).foregroundStyle(DGColor.ink4).lineLimit(1)
                    if let price = CoachModelPricingText.line(for: model.pricing) {
                        Text(price).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
                    }
                    if !model.supportsTools {
                        Text("No tool support — the coach can't read your log with this model")
                            .font(DGFont.footnote)
                            .foregroundStyle(DGColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DGSpace.s2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DGColor.coralText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .padding(.vertical, DGSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgControl)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(accessibilityLabel(model))
    }

    private func accessibilityLabel(_ model: OpenRouterWire.Model) -> String {
        var parts = [model.name]
        if let price = CoachModelPricingText.line(for: model.pricing) { parts.append(price) }
        if !model.supportsTools { parts.append("no tool support") }
        return parts.joined(separator: ", ")
    }

    private func load() async {
        phase = .loading
        let client = OpenRouterClient(apiKey: CoachChatSettings.keyProvider)
        do {
            models = try await client.models()
            phase = .loaded
        } catch {
            let typed = (error as? OpenRouterError) ?? .network(error)
            phase = .failed(CoachChatErrorCopy.banner(for: typed).message)
        }
    }
}

#Preview {
    CoachModelPickerSheet(role: .reviewer).environment(Preferences())
}
