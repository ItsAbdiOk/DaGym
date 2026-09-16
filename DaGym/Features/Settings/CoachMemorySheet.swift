import GymCore
import SwiftUI

/// Settings › Coach › Coach memory: every fact the coach has been told to keep in mind across
/// chats, newest first, with its topic and date. Swipe or tap to forget one; "Forget
/// everything" removes the file. The list is local to this phone (`CoachMemoryFile`), and the
/// same list is printed into the coach's instructions, so what is shown here is exactly what
/// the model knows.
struct CoachMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var facts: [CoachMemoryFact] = []
    @State private var confirmingForgetAll = false

    private let memory = CoachMemoryFile.standard()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s6) {
                        caption(
                            "What the coach remembers between chats — injuries, preferences, schedule "
                                + "and equipment changes, goals. It never remembers weights or sets; "
                                + "those come from your log. Kept on this phone only."
                        )
                        list
                        if !facts.isEmpty {
                            Button("Forget everything", role: .destructive) { confirmingForgetAll = true }
                                .buttonStyle(.dgControl)
                                .dgLabel(DGColor.danger)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .dgCard(padding: 0)
                                .accessibilityIdentifier(A11yID.coachMemoryForgetAll)
                        }
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.vertical, DGSpace.s3)
                }
            }
            .navigationTitle("Coach memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(DGColor.surface1)
        .task { reload() }
        .confirmationDialog(
            "Forget everything?", isPresented: $confirmingForgetAll, titleVisibility: .visible
        ) {
            Button("Forget everything", role: .destructive, action: forgetEverything)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every remembered fact. Your chats are kept.")
        }
    }

    @ViewBuilder
    private var list: some View {
        VStack(spacing: 0) {
            if facts.isEmpty {
                Text("Nothing remembered yet. Tell the coach about an injury, a schedule or a preference "
                    + "and it will keep it here.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DGSpace.s5)
            } else {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    if index > 0 { CoachChatSettingsDivider() }
                    CoachMemoryRow(fact: fact, onForget: { forget(fact) })
                }
            }
        }
        .dgCard(padding: 0)
        .accessibilityIdentifier(A11yID.coachMemoryList)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DGFont.subhead)
            .foregroundStyle(DGColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func reload() {
        facts = memory?.facts() ?? []
    }

    private func forget(_ fact: CoachMemoryFact) {
        try? memory?.forget(id: fact.id)
        reload()
    }

    private func forgetEverything() {
        try? memory?.forgetEverything()
        reload()
    }
}

/// One fact: the text, its topic and date, and a Forget button.
private struct CoachMemoryRow: View {
    var fact: CoachMemoryFact
    var onForget: () -> Void

    var body: some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.text)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
            }
            Spacer()
            Button("Forget", role: .destructive, action: onForget)
                .buttonStyle(.dgControl)
                .dgLabel(DGColor.danger)
                .accessibilityLabel("Forget: \(fact.text)")
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s3)
        .frame(minHeight: 52)
    }

    private var detail: String {
        let created = fact.createdAt.formatted(date: .abbreviated, time: .omitted)
        var parts = ["\(fact.topic.displayName) · \(created)"]
        if let expiresAt = fact.expiresAt {
            parts.append("until \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    CoachMemorySheet()
}
