import GymCore
import SwiftUI

/// The cloud-coach half of Settings → Coach: the OpenRouter key row (add / change / remove),
/// the two model rows (the coach that drafts, the second opinion that reviews — each opens
/// the live picker), a cost hint with both prices, the "Coach usage" row (tokens and dollars
/// spent, `CoachUsageSheet`), the consent state, and a "What's sent"
/// disclosure listing every tool the coach can call. The first key save presents the consent
/// screen; declining keeps the key but leaves `coachChatConsentGiven` false, so nothing is
/// ever sent.
struct CoachChatSettingsCard: View {
    @Environment(Preferences.self) private var preferences
    @State private var hasKey = CoachChatSettings.hasAPIKey
    @State private var showingKeySheet = false
    @State private var pickerRole: CoachModelRole?
    @State private var showingConsent = false
    @State private var showingWhatIsSent = false
    @State private var showingUsage = false
    @State private var showingMemory = false
    /// Prices by model id from one GET /models, for the cost hint; empty until it lands.
    @State private var pricing: [String: OpenRouterWire.Pricing] = [:]

    var body: some View {
        VStack(spacing: 0) {
            caption(
                "Talk to a coach that reads your whole log, using your own OpenRouter key. Your key "
                    + "stays in the Keychain; your training data goes to OpenRouter and the model you "
                    + "pick, only when you ask a question."
            )
            CoachChatSettingsDivider()
            navigationRow(
                label: "OpenRouter API key", value: hasKey ? "Saved" : "Not set",
                action: { showingKeySheet = true }
            )
            .accessibilityIdentifier(A11yID.coachKeyRow)
            CoachChatSettingsDivider()
            navigationRow(label: "Coach", value: coachName, action: { pickerRole = .coach })
            .accessibilityIdentifier(A11yID.coachModelRow)
            CoachChatSettingsDivider()
            navigationRow(
                label: "Second opinion", value: reviewerName, action: { pickerRole = .reviewer }
            )
            .accessibilityIdentifier(A11yID.coachReviewerRow)
            CoachChatSettingsDivider()
            caption(costHint).accessibilityIdentifier(A11yID.coachCostHint)
            CoachChatSettingsDivider()
            navigationRow(label: "Coach usage", value: "Tokens and cost", action: { showingUsage = true })
                .accessibilityIdentifier(A11yID.coachUsageRow)
            CoachChatSettingsDivider()
            navigationRow(label: "Coach memory", value: "What it remembers", action: { showingMemory = true })
                .accessibilityIdentifier(A11yID.coachMemoryRow)
            if hasKey {
                CoachChatSettingsDivider()
                consentRow
            }
            CoachChatSettingsDivider()
            whatIsSent
        }
        .dgCard(padding: 0)
        .sheet(isPresented: $showingKeySheet) {
            OpenRouterKeySheet(hasKey: hasKey, onSave: saveKey, onRemove: removeKey)
        }
        .sheet(item: $pickerRole) { role in CoachModelPickerSheet(role: role) }
        .sheet(isPresented: $showingUsage) { CoachUsageSheet() }
        .sheet(isPresented: $showingMemory) { CoachMemorySheet() }
        .sheet(isPresented: $showingConsent) {
            CoachChatConsentSheet(
                onAgree: { preferences.coachChatConsentGiven = true; showingConsent = false },
                onCancel: { showingConsent = false }
            )
        }
        .onAppear { hasKey = CoachChatSettings.hasAPIKey }
        .task(id: hasKey) { await loadPricing() }
    }

    private var coachName: String { CoachChatConfiguration.displayName(forModelID: preferences.coachModelID) }

    private var reviewerName: String {
        preferences.coachReviewerModelID.map(CoachChatConfiguration.displayName(forModelID:)) ?? "Off"
    }

    private var costHint: String {
        CoachChatCostHint.line(
            drafterModelID: preferences.coachModelID, drafterPricing: pricing[preferences.coachModelID],
            reviewerModelID: preferences.coachReviewerModelID,
            reviewerPricing: preferences.coachReviewerModelID.flatMap { pricing[$0] }
        )
    }

    /// One fetch per key change, only when there is a key to fetch with; a failure leaves the
    /// hint without prices rather than showing an error in Settings.
    private func loadPricing() async {
        guard hasKey, pricing.isEmpty else { return }
        let client = OpenRouterClient(apiKey: CoachChatSettings.keyProvider)
        guard let models = try? await client.models() else { return }
        let pairs = models.compactMap { model in model.pricing.map { (model.id, $0) } }
        pricing = Dictionary(pairs) { first, _ in first }
    }

    private var consentRow: some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sending your data").font(DGFont.body).foregroundStyle(DGColor.ink1)
                Text(preferences.coachChatConsentGiven ? "Agreed" : "Not yet agreed")
                    .font(DGFont.footnote)
                    .foregroundStyle(preferences.coachChatConsentGiven ? DGColor.success : DGColor.ink3)
            }
            Spacer()
            if preferences.coachChatConsentGiven {
                Button("Revoke") { preferences.coachChatConsentGiven = false }
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.danger)
            } else {
                Button("Review") { showingConsent = true }
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.coralText)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var whatIsSent: some View {
        Button { showingWhatIsSent.toggle() } label: {
            HStack {
                Text("What's sent").font(DGFont.body).foregroundStyle(DGColor.ink1)
                Spacer()
                Image(systemName: showingWhatIsSent ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 52)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(showingWhatIsSent ? "Hide what's sent" : "Show what's sent")
        .accessibilityIdentifier(A11yID.coachWhatIsSent)
        if showingWhatIsSent {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text(
                    "Every question goes with a short profile (units, goal, bodyweight, equipment), "
                        + "the facts in Coach memory and the conversation so far. The coach then reads "
                        + "only what it asks for, through these tools:"
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                ForEach(CoachChatToolCatalog.tools) { tool in
                    HStack(alignment: .top, spacing: DGSpace.s2) {
                        Text("•").font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                        Text(CoachChatMessage.label(forTool: tool.name))
                            .font(DGFont.footnote)
                            .foregroundStyle(DGColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(
                    "With a second opinion on, each proposal — with your last question and the coach's "
                        + "reply — is also sent to that model, which can read the same tools before it "
                        + "agrees or proposes its own version."
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DGSpace.s1)
                Text("Chats are kept on this phone only and never sync through iCloud.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DGSpace.s1)
            }
            .padding(.horizontal, DGSpace.s5)
            .padding(.bottom, DGSpace.s4)
        }
    }

    private func navigationRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
                Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
                Spacer()
                HStack(spacing: DGSpace.s2) {
                    Text(value).font(DGFont.subhead).foregroundStyle(DGColor.ink3).lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 52)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("\(label): \(value)")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DGFont.subhead)
            .foregroundStyle(DGColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DGSpace.s5)
            .padding(.vertical, DGSpace.s3)
    }

    private func saveKey(_ key: String) {
        CoachChatSettings.saveAPIKey(key)
        hasKey = CoachChatSettings.hasAPIKey
        showingKeySheet = false
        // Consent is asked once, the first time a key lands — never re-asked on a key change.
        if hasKey, !preferences.coachChatConsentGiven { showingConsent = true }
    }

    private func removeKey() {
        CoachChatSettings.removeAPIKey()
        hasKey = false
        showingKeySheet = false
    }
}

struct CoachChatSettingsDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    ScrollView {
        CoachChatSettingsCard().padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
