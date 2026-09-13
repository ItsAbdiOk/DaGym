import SwiftUI

/// The entry point to the gym check-in card (features.md adopt 6): a glass row that opens
/// `GymCardSheet`. Reads "Gym card · PureGym" once a card exists, "Add your gym card" before.
/// Mount it wherever the lead wants the check-in to live (Home header or Settings → Training);
/// Pass `isPresented` so `RootView` can open the sheet straight from the "Show gym card" intent.
struct CheckInCardButton: View {
    @Environment(WorkoutStore.self) private var store
    @State private var cardName: String?
    @State private var localPresented = false
    /// External control (the intent hand-off); nil means the button owns its own presentation.
    private var external: Binding<Bool>?

    init(isPresented: Binding<Bool>? = nil) {
        external = isPresented
    }

    private var isPresented: Binding<Bool> { external ?? $localPresented }

    var body: some View {
        Button {
            isPresented.wrappedValue = true
        } label: {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coralText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gym card")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                    Text(cardName ?? "Add your gym card")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.rowHeight)
            .dgCard(padding: 0)
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(cardName.map { "Gym card, \($0)" } ?? "Add your gym card")
        .task { refresh() }
        .onChange(of: store.changeToken) { _, _ in refresh() }
        .sheet(isPresented: isPresented) {
            GymCardSheet()
        }
    }

    private func refresh() {
        cardName = store.lastUsedGymCard()?.name
    }
}

#Preview {
    if let store = PreviewStore.make() {
        CheckInCardButton()
            .padding()
            .background(DGColor.bgBase)
            .environment(store)
    }
}
