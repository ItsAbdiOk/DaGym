import SwiftUI
import UIKit

/// One card in the rail (the redesign prototype's `sCard`): the name in small bold, the code
/// drawn large on a solid white card, and the number under it in tracked monospace. Solid
/// white, not the frosted card: a scanner needs contrast, not a wash showing through.
struct GymCardFace: View {
    var card: GymCardInfo
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var renaming = false
    @State private var newName = ""
    /// Rendered once per value/symbology via `.task(id:)` — never inside `body`, which re-runs
    /// on every rail swipe and alert toggle.
    @State private var rendered: UIImage?
    @State private var renderFailed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            HStack(alignment: .top) {
                Text(card.name)
                    .font(DGFont.footnote.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .lineLimit(2)
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
                        .foregroundStyle(Color.black.opacity(0.46))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Card options")
            }
            codeImage
            Text(card.value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .tracking(2.5)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            Text(card.symbology.title)
                .dgLabel(Color.black.opacity(0.46))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x3C2814).opacity(scheme == .dark ? 0.5 : 0.14), radius: 17, y: 7)
        .task(id: [card.value, card.symbology.rawValue]) {
            let value = card.value
            let symbology = card.symbology
            let image = await Task.detached(priority: .userInitiated) {
                BarcodeRenderer.image(value: value, symbology: symbology)
            }.value
            guard !Task.isCancelled else { return }
            rendered = image
            renderFailed = image == nil
        }
        .alert("Rename card", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { onRename(newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var codeHeight: CGFloat { card.symbology.isTwoDimensional ? 220 : 104 }

    @ViewBuilder
    private var codeImage: some View {
        if let image = rendered {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: codeHeight)
                .accessibilityLabel("\(card.symbology.title) code for \(card.name)")
        } else if renderFailed {
            Text("This card's value can't be drawn as a \(card.symbology.title) code.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: codeHeight)
        } else {
            // First render in flight: hold the code's footprint so the card doesn't jump.
            Color.white
                .frame(maxWidth: .infinity)
                .frame(height: codeHeight)
        }
    }
}
