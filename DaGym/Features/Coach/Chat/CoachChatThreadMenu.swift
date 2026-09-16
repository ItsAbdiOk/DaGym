import SwiftUI

/// The toolbar menu for switching, starting and deleting threads: New chat, the ten most
/// recent threads (the open one ticked), and Delete for a thread with messages.
struct CoachChatThreadMenu: View {
    var threads: [CoachChatThreadSummary]
    var currentID: UUID?
    var canDelete: Bool
    var onNew: () -> Void
    var onOpen: (UUID) -> Void
    var onDelete: () -> Void

    var body: some View {
        Menu {
            Button(action: onNew) { Label("New chat", systemImage: "plus") }
            if !threads.isEmpty {
                Section("Recent") {
                    ForEach(threads.prefix(10)) { summary in
                        Button {
                            onOpen(summary.id)
                        } label: {
                            if summary.id == currentID {
                                Label(summary.title, systemImage: "checkmark")
                            } else {
                                Text(summary.title)
                            }
                        }
                    }
                }
            }
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete this chat", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Chats")
        }
        .accessibilityIdentifier(A11yID.coachChatThreadMenu)
    }
}
