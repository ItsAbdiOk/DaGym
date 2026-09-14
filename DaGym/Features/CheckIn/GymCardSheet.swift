import PhotosUI
import SwiftUI
import UIKit

/// The gym check-in card (features.md adopt 6): a horizontal rail of every saved card, each
/// regenerated from its payload at full screen brightness so the front-desk scanner reads it
/// first time. Adding a card scans with the camera, reads a photo, or takes a typed number.
struct GymCardSheet: View {
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
    @State private var brightness = ScreenBrightness()

    var body: some View {
        ZStack {
            AmbientWash()
            VStack(spacing: DGSpace.s4) {
                header
                if cards.isEmpty {
                    EmptyState(
                        symbol: "qrcode.viewfinder", title: "No Gym Card Yet",
                        message: "Scan the barcode on your membership card once and it lives here."
                    )
                } else {
                    rail
                }
                addOptions
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s3)
            .padding(.bottom, DGSpace.s6)
        }
        .task { refresh() }
        .onChange(of: store.changeToken) { _, _ in refresh() }
        .onChange(of: selectedID) { _, id in
            if let id { store.markGymCardUsed(id: id) }
        }
        .onAppear { brightness.raise() }
        .onDisappear { brightness.restore() }
        .fullScreenCover(isPresented: $showingScanner) { scannerCover }
        .onChange(of: pickedItem) { _, item in
            if let item { Task { await readPhoto(item) } }
        }
        .alert("Name This Card", isPresented: pendingScanBinding, presenting: pendingScan) { scan in
            TextField("e.g. PureGym", text: $pendingName)
            Button("Save") { saveCard(scan) }
            Button("Cancel", role: .cancel) { pendingScan = nil }
        } message: { scan in
            Text("\(scan.symbology.title) · \(scan.value)")
        }
        .alert("Enter Card Number", isPresented: $showingManualEntry) {
            TextField("Membership number", text: $manualValue)
            Button("Next") {
                pendingScan = PendingScan(value: manualValue, symbology: .code128)
                manualValue = ""
            }
            Button("Cancel", role: .cancel) { manualValue = "" }
        } message: {
            Text("Typed numbers are shown as a Code 128 barcode.")
        }
        .alert("No Barcode Found", isPresented: $photoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a sharper photo with the whole code in frame, or type the number instead.")
        }
    }

    private var header: some View {
        HStack {
            Text("Gym Card")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "xmark", size: 36, accessibilityLabel: "Close") { dismiss() }
                .dgTapTarget()
        }
    }

    private var rail: some View {
        TabView(selection: $selectedID) {
            ForEach(cards) { card in
                GymCardFace(card: card, onRename: { rename(card, to: $0) }, onDelete: { delete(card) })
                    .tag(Optional(card.id))
                    .padding(.horizontal, DGSpace.s2)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 400)
    }

    private var addOptions: some View {
        VStack(spacing: DGSpace.s2) {
            if GymCardScannerView.isSupported {
                DGPrimaryButton(title: "Scan Card", symbol: "camera.viewfinder") { showingScanner = true }
            }
            HStack(spacing: DGSpace.s2) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    SecondaryLabel(title: "From Photo", symbol: "photo")
                }
                .buttonStyle(.dgControl)
                Button {
                    showingManualEntry = true
                } label: {
                    SecondaryLabel(title: "Type Number", symbol: "keyboard")
                }
                .buttonStyle(.dgControl)
            }
        }
    }

    private var scannerCover: some View {
        ZStack(alignment: .topTrailing) {
            GymCardScannerView { value, symbology in
                showingScanner = false
                pendingScan = PendingScan(value: value, symbology: symbology)
            }
            .ignoresSafeArea()
            DGIconButton(symbol: "xmark", accessibilityLabel: "Cancel scan") { showingScanner = false }
                .dgTapTarget()
                .padding(DGSpace.s4)
        }
    }

    private var pendingScanBinding: Binding<Bool> {
        Binding(get: { pendingScan != nil }, set: { if !$0 { pendingScan = nil } })
    }

    private func refresh() {
        cards = store.gymCards()
        if selectedID == nil || !cards.contains(where: { $0.id == selectedID }) {
            selectedID = store.lastUsedGymCard()?.id
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

/// One card in the rail: name, the regenerated code on a white field, the raw value underneath.
private struct GymCardFace: View {
    var card: GymCardInfo
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            HStack {
                Text(card.name)
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        newName = card.name
                        renaming = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DGColor.ink3)
                        .frame(width: DGTap.min, height: DGTap.min)
                }
                .accessibilityLabel("Card options")
            }
            codeImage
            Text(card.value)
                .font(DGFont.footnote.monospacedDigit())
                .foregroundStyle(DGColor.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(card.symbology.title).dgLabel()
        }
        .dgCard()
        .alert("Rename Card", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { onRename(newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var codeImage: some View {
        if let image = BarcodeRenderer.image(value: card.value, symbology: card.symbology) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: card.symbology.isTwoDimensional ? 220 : 120)
                .padding(DGSpace.s4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
                .accessibilityLabel("\(card.symbology.title) code for \(card.name)")
        } else {
            Text("This card's value can't be drawn as a \(card.symbology.title) code.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.danger)
        }
    }
}

/// Glass secondary button label ("From Photo", "Type Number").
private struct SecondaryLabel: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
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
