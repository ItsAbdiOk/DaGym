import SwiftUI
import UIKit

/// Compares two photos of the same pose — side-by-side, or a slider wipe between them using a
/// mask + `DragGesture` (plan.md §6.4). Defaults to the oldest and newest photo in `photos`
/// (`WorkoutStore.photos(pose:)` returns newest-first, so that's the last and first index).
/// `photos` carries thumbnails only; the two photos on screen are fetched at full size through
/// `WorkoutStore.photo(id:)` as they're picked and decoded once into `fullImages` — `body`
/// re-runs on every slider frame, so it must never decode.
struct PhotoCompareView: View {
    var pose: ProgressPhotoPose
    var photos: [ProgressPhotoInfo]

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var beforeIndex: Int
    @State private var afterIndex: Int
    @State private var isSideBySide = true
    @State private var sliderFraction: CGFloat = 0.5
    @State private var fullImages: [UUID: UIImage] = [:]

    init(pose: ProgressPhotoPose, photos: [ProgressPhotoInfo]) {
        self.pose = pose
        self.photos = photos
        _beforeIndex = State(initialValue: max(photos.count - 1, 0))
        _afterIndex = State(initialValue: 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                VStack(spacing: DGSpace.s5) {
                    modePicker
                    if !photos.isEmpty {
                        pickers
                        if isSideBySide { sideBySide } else { slider }
                    }
                    Spacer()
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
            }
            .navigationTitle("Compare \(pose.label)")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: [beforeIndex, afterIndex]) { await loadFullImages() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: DGSpace.s2) {
            DGChip(title: "Side By Side", selected: isSideBySide) { isSideBySide = true }
            DGChip(title: "Slider", selected: !isSideBySide) { isSideBySide = false }
        }
    }

    private var pickers: some View {
        HStack(spacing: DGSpace.s3) {
            photoPicker(title: "Before", index: $beforeIndex)
            photoPicker(title: "After", index: $afterIndex)
        }
    }

    private func photoPicker(title: String, index: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text(title).dgLabel()
            Menu {
                ForEach(photos.indices, id: \.self) { candidate in
                    Button(Self.dateLabel(photos[candidate].date)) { index.wrappedValue = candidate }
                }
            } label: {
                Text(Self.dateLabel(photos[index.wrappedValue].date))
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink1)
                    .padding(.horizontal, DGSpace.s3)
                    .frame(minHeight: 36)
                    .dgGlass(.thin, radius: DGRadius.sm)
            }
        }
    }

    private var sideBySide: some View {
        HStack(spacing: DGSpace.s2) {
            photoCard(index: beforeIndex)
            photoCard(index: afterIndex)
        }
    }

    private func photoCard(index: Int) -> some View {
        VStack(spacing: DGSpace.s1) {
            image(for: index)
                .aspectRatio(3 / 4, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            Text(Self.dateLabel(photos[index].date)).dgLabel()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress photo, \(Self.dateLabel(photos[index].date))")
    }

    private var slider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                image(for: beforeIndex).aspectRatio(3 / 4, contentMode: .fill).frame(width: width)
                image(for: afterIndex)
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .frame(width: width)
                    .mask(alignment: .leading) { Rectangle().frame(width: width * sliderFraction) }
                Rectangle().fill(DGColor.coral).frame(width: 2).offset(x: width * sliderFraction - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            .gesture(dragGesture(width: width))
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        // A drag has no VoiceOver equivalent; swipe up/down moves the wipe in 10 % steps.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo comparison wipe")
        .accessibilityValue("\(Int((sliderFraction * 100).rounded())) percent after photo")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = direction == .increment ? 0.1 : -0.1
            sliderFraction = min(max(sliderFraction + step, 0), 1)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                sliderFraction = min(max(value.location.x / width, 0), 1)
            }
    }

    /// Fetches the full-size bytes for the two picked photos and decodes them off-main, falling
    /// back to the thumbnail bytes when the full row is gone. Cached per photo id, so re-picking
    /// an already-shown photo is free.
    private func loadFullImages() async {
        for index in [beforeIndex, afterIndex] {
            guard let photo = photos[safe: index], fullImages[photo.id] == nil else { continue }
            let data = store.photo(id: photo.id)?.imageData ?? photo.imageData ?? photo.thumbnailData
            guard let image = await PhotoDecoder.decodeForDisplay(data), !Task.isCancelled else { continue }
            fullImages[photo.id] = image
        }
    }

    private func image(for index: Int) -> some View {
        Group {
            if let photo = photos[safe: index], let uiImage = fullImages[photo.id] {
                Image(uiImage: uiImage).resizable()
            } else {
                Rectangle().fill(DGColor.surface2)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func dateLabel(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    if let store = PreviewStore.make() {
        PhotoCompareView(pose: .front, photos: [])
            .environment(store)
            .environment(Preferences())
    }
}
