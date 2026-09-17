import PhotosUI
import SwiftUI
import UIKit

/// The gym check-in card (features.md adopt 6): a white card with the membership barcode drawn
/// large and the number under it, regenerated from its payload at full screen brightness so
/// the front-desk scanner reads it first time; several cards page sideways. Adding a card scans
/// with the camera, reads a photo, or takes a typed number.
///
/// Lives two ways: pushed from the You hub (`isPushed`, no close button — the system back is
/// the "‹ You"), and as a sheet from Today's barcode button, the Siri intent and the check-in
/// row, where it wraps itself in a stack for the title and a Done button.
struct GymCardSheet: View {
    var isPushed = false

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [GymCardInfo] = []
    @State private var selectedID: UUID?
    @State private var showingScanner = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingScan: PendingScan?
    @State private var pendingName = ""
    @State private var manualValue = ""
    @State private var showingManualEntry = false
    @State private var photoFailed = false
    @State private var scannerFailure: String?
    @State private var brightness = ScreenBrightness()
    @State private var wallet = WalletPassService()

    var body: some View {
        if isPushed {
            screen
        } else {
            NavigationStack {
                screen.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var screen: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(spacing: DGSpace.s4) {
                    if cards.isEmpty {
                        emptyState
                    } else {
                        rail
                        if let selectedCard, wallet.isAvailable {
                            GymCardWalletRow(card: selectedCard, service: wallet)
                        }
                        Text(Self.footnote)
                            .font(DGFont.footnote)
                            .foregroundStyle(DGColor.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DGSpace.s1)
                    }
                    addOptions
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s5)
                .padding(.bottom, DGSpace.s6)
            }
        }
        .navigationTitle("Gym card")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: store.changeToken) { _, _ in refresh() }
        .onAppear { brightness.raise() }
        .onDisappear {
            brightness.restore()
            // Stamped once here, not per rail swipe: `markGymCardUsed` is a fetch + save (and a
            // CloudKit export with iCloud on), and only the card left showing matters.
            if let selectedID { store.markGymCardUsed(id: selectedID) }
        }
        .fullScreenCover(isPresented: $showingScanner) { scannerCover }
        .onChange(of: pickedItem) { _, item in
            if let item { Task { await readPhoto(item) } }
        }
        .alert("Name this card", isPresented: pendingScanBinding, presenting: pendingScan) { scan in
            TextField("e.g. PureGym", text: $pendingName)
            Button("Save") { saveCard(scan) }
            Button("Cancel", role: .cancel) { pendingScan = nil }
        } message: { scan in
            Text("\(scan.symbology.title) · \(scan.value)")
        }
        .alert("Enter card number", isPresented: $showingManualEntry) {
            TextField("Membership number", text: $manualValue)
            Button("Next") {
                pendingScan = PendingScan(value: manualValue, symbology: .code128)
                manualValue = ""
            }
            Button("Cancel", role: .cancel) { manualValue = "" }
        } message: {
            Text("Typed numbers are shown as a Code 128 barcode.")
        }
        .alert("No barcode found", isPresented: $photoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a sharper photo with the whole code in frame, or type the number instead.")
        }
        .alert("Camera unavailable", isPresented: scannerFailureBinding, presenting: scannerFailure) { _ in
            Button("OK", role: .cancel) { scannerFailure = nil }
        } message: { reason in
            Text("\(reason) Take a photo of the card or type the number instead.")
        }
    }

    /// The prototype's footnote — what the screen does on its own, and the Siri route in.
    static let footnote =
        "Screen brightness is raised while the card is open. Also available from Siri: “Show gym card”."

    private var selectedCard: GymCardInfo? {
        cards.first { $0.id == selectedID } ?? cards.first
    }

    private var emptyState: some View {
        EmptyState(
            symbol: "barcode.viewfinder", title: "Scan your gym card",
            message: "Scan the barcode on your membership card once and it lives here, bright enough for the desk scanner."
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, DGSpace.s6)
        .dgCard(radius: 22)
    }

    private var rail: some View {
        TabView(selection: $selectedID) {
            ForEach(cards) { card in
                GymCardFace(card: card, onRename: { rename(card, to: $0) }, onDelete: { delete(card) })
                    .tag(Optional(card.id))
                    .padding(.horizontal, DGSpace.s1)
                    .padding(.bottom, cards.count > 1 ? DGSpace.s6 : 0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        // A paged TabView has no intrinsic height: the tallest face (a square 2-D code) sets it.
        .frame(height: railHeight)
        .padding(.horizontal, -DGSpace.s1)
    }

    private var railHeight: CGFloat {
        let square = cards.contains { $0.symbology.isTwoDimensional }
        return (square ? 380 : 260) + (cards.count > 1 ? DGSpace.s6 : 0)
    }

    /// Scan / photo / typed number. The scan is the primary action before any card exists and
    /// a quieter "add another" once one does.
    private var addOptions: some View {
        VStack(spacing: DGSpace.s2) {
            if GymCardScannerView.isSupported {
                if cards.isEmpty {
                    DGPrimaryButton(title: "Scan card", symbol: "camera.viewfinder") { showingScanner = true }
                } else {
                    Button {
                        showingScanner = true
                    } label: {
                        SecondaryLabel(title: "Scan another card", symbol: "camera.viewfinder")
                    }
                    .buttonStyle(.dgControl)
                }
            }
            HStack(spacing: DGSpace.s2) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    SecondaryLabel(title: "From photo", symbol: "photo")
                }
                .buttonStyle(.dgControl)
                Button {
                    showingManualEntry = true
                } label: {
                    SecondaryLabel(title: "Type number", symbol: "keyboard")
                }
                .buttonStyle(.dgControl)
            }
        }
        .padding(.top, cards.isEmpty ? 0 : DGSpace.s2)
    }

    private var scannerCover: some View {
        ZStack(alignment: .topTrailing) {
            GymCardScannerView(
                onScan: { value, symbology in
                    showingScanner = false
                    pendingScan = PendingScan(value: value, symbology: symbology)
                },
                onFailure: { reason in
                    showingScanner = false
                    scannerFailure = reason
                }
            )
            .ignoresSafeArea()
            DGIconButton(symbol: "xmark", accessibilityLabel: "Cancel scan") { showingScanner = false }
                .padding(DGSpace.s4)
        }
    }

    private var pendingScanBinding: Binding<Bool> {
        Binding(get: { pendingScan != nil }, set: { if !$0 { pendingScan = nil } })
    }

    private var scannerFailureBinding: Binding<Bool> {
        Binding(get: { scannerFailure != nil }, set: { if !$0 { scannerFailure = nil } })
    }

    private func refresh() {
        cards = store.gymCards()
        if selectedID == nil || !cards.contains(where: { $0.id == selectedID }) {
            selectedID = store.lastUsedGymCard()?.id ?? cards.first?.id
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let found = await PhotoBarcodeDetector.detect(in: data) else {
            photoFailed = true
            return
        }
        pendingScan = PendingScan(value: found.value, symbology: found.symbology)
    }

    private func saveCard(_ scan: PendingScan) {
        let added = store.addGymCard(name: pendingName, value: scan.value, symbology: scan.symbology)
        pendingName = ""
        pendingScan = nil
        refresh()
        if let added { selectedID = added.id }
    }

    private func rename(_ card: GymCardInfo, to name: String) {
        store.renameGymCard(id: card.id, name: name)
        refresh()
    }

    private func delete(_ card: GymCardInfo) {
        store.deleteGymCard(id: card.id)
        refresh()
    }
}

/// A scan or typed number waiting for its name.
private struct PendingScan: Identifiable {
    let id = UUID()
    var value: String
    var symbology: GymCardSymbology
}

/// Glass secondary button label ("From photo", "Type number").
private struct SecondaryLabel: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(DGFont.condensedLabel(13))
        }
        .foregroundStyle(DGColor.ink1)
        .frame(maxWidth: .infinity)
        .frame(height: DGTap.min)
        .dgGlass(.regular, in: Capsule())
    }
}

/// Pushes the screen to full brightness while a card is on screen and puts it back after —
/// scanners read a bright code far more reliably than a dim one.
@MainActor
struct ScreenBrightness {
    private var previous: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    mutating func raise() {
        guard previous == nil, let screen else { return }
        previous = screen.brightness
        screen.brightness = 1
    }

    mutating func restore() {
        guard let previous, let screen else { return }
        screen.brightness = previous
        self.previous = nil
    }
}

#Preview {
    if let store = PreviewStore.make() {
        GymCardSheet()
            .environment(store)
    }
}
