import GymCore
import SwiftUI

/// Settings › Coach › Coach usage: what the cloud coach has cost. The top card is the running
/// ledger across every thread (tokens in and out and dollars, per model, since first use or
/// the last reset) with "Reset statistics", which zeroes those counters and nothing else. Below
/// it, every saved chat with its own usage, so a long thread that ran up the bill can be found
/// and deleted from the chat. Dollars are OpenRouter's own figure when it reported one, else an
/// estimate from `CoachModelPricing`; a model the table does not know shows tokens only.
struct CoachUsageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ledger = CoachChatUsageLedger()
    @State private var threads: [CoachChatThread] = []
    @State private var confirmingReset = false

    private let ledgerStore = CoachChatUsageLedgerStore.standard
    private let archive = CoachChatArchive.standard()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s6) {
                        totalsSection
                        threadsSection
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.vertical, DGSpace.s3)
                }
            }
            .navigationTitle("Coach usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(DGColor.surface1)
        .task { reload() }
        .confirmationDialog(
            "Reset statistics?", isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Reset statistics", role: .destructive, action: reset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Zeroes the totals above. Your chats and their own usage are kept.")
        }
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("All chats").dgLabel()
            VStack(spacing: 0) {
                caption(sinceLine)
                CoachChatSettingsDivider()
                CoachUsageRow(
                    title: "Total", detail: CoachUsageText.inOut(
                        promptTokens: ledger.promptTokens, completionTokens: ledger.completionTokens
                    ),
                    cost: CoachUsageText.cost(ledger.estimatedUSD(), reported: ledger.isFullyReported)
                )
                .accessibilityIdentifier(A11yID.coachUsageTotal)
                ForEach(ledger.modelsBySpend, id: \.self) { model in
                    CoachChatSettingsDivider()
                    modelRow(model, usage: ledger.byModel[model])
                }
                CoachChatSettingsDivider()
                Button("Reset statistics", role: .destructive) { confirmingReset = true }
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.danger)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .disabled(ledger.isEmpty)
                    .accessibilityIdentifier(A11yID.coachUsageReset)
            }
            .dgCard(padding: 0)
        }
    }

    private var sinceLine: String {
        guard let since = ledger.since else {
            return "Nothing sent yet. Totals appear after the first reply."
        }
        let replies = ledger.replies == 1 ? "1 reply" : "\(ledger.replies) replies"
        return "\(replies) since \(since.formatted(date: .abbreviated, time: .omitted)). Dollar figures "
            + "marked ≈ are estimates from list prices; the rest are what OpenRouter reported."
    }

    // MARK: - Threads

    @ViewBuilder
    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("By chat").dgLabel()
            VStack(spacing: 0) {
                if threads.isEmpty {
                    caption("No saved chats.")
                } else {
                    ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                        if index > 0 { CoachChatSettingsDivider() }
                        threadRows(thread)
                    }
                }
            }
            .dgCard(padding: 0)
        }
    }

    @ViewBuilder
    private func threadRows(_ thread: CoachChatThread) -> some View {
        CoachUsageRow(
            title: thread.title,
            subtitle: thread.updatedAt.formatted(date: .abbreviated, time: .shortened),
            detail: CoachUsageText.inOut(
                promptTokens: thread.usage.promptTokens, completionTokens: thread.usage.completionTokens
            ),
            cost: CoachUsageText.cost(thread.usage.estimatedUSD(), reported: thread.usage.costUSD != nil)
        )
        ForEach(thread.usage.byModel.keys.sorted(), id: \.self) { model in
            modelRow(model, usage: thread.usage.byModel[model])
                .padding(.leading, DGSpace.s4)
        }
    }

    private func modelRow(_ model: String, usage: CoachChatModelUsage?) -> some View {
        let usage = usage ?? CoachChatModelUsage()
        return CoachUsageRow(
            title: CoachChatConfiguration.displayName(forModelID: model), isSecondary: true,
            detail: CoachUsageText.inOut(
                promptTokens: usage.promptTokens, completionTokens: usage.completionTokens
            ),
            cost: CoachUsageText.cost(usage.estimatedUSD(model: model), reported: usage.costUSD != nil)
        )
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

    // MARK: - Actions

    private func reload() {
        ledger = ledgerStore.load()
        threads = archive?.threads() ?? []
    }

    private func reset() {
        ledgerStore.reset(at: Date())
        ledger = ledgerStore.load()
    }
}

/// One usage line: a title (a thread, a model), tokens in and out, and the cost when known.
private struct CoachUsageRow: View {
    var title: String
    var subtitle: String?
    var isSecondary = false
    var detail: String
    var cost: String?

    var body: some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isSecondary ? DGFont.subhead : DGFont.body)
                    .foregroundStyle(isSecondary ? DGColor.ink2 : DGColor.ink1)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(cost ?? "—")
                    .font(DGFont.title3)
                    .foregroundStyle(cost == nil ? DGColor.ink4 : DGColor.ink1)
                Text(detail).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CoachUsageSheet()
}
