import SwiftData
import SwiftUI
import UIKit

/// Progress Photos — pose-segmented photo grid with a date + bodyweight caption per photo, an
/// "Add Photo" entry into `PhotoCaptureView`, and a "Compare" entry into `PhotoCompareView`
/// (plan.md §6.4). `BodyView` wraps this in `PhotoLockGate` when `preferences.lockPhotos` is on.
struct ProgressPhotosView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var pose: ProgressPhotoPose = .front
    @State private var photos: [ProgressPhotoInfo] = []
    @State private var isCapturing = false
    @State private var isComparing = false
    @State private var pendingDelete: ProgressPhotoInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        poseChips
                        grid
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s14)
                }
            }
            .navigationTitle("Progress Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Compare") { isComparing = true }
                        .disabled(photos.count < 2)
                }
            }
            .safeAreaInset(edge: .bottom) {
                DGPrimaryButton(title: "Add Photo", symbol: "camera.fill") { isCapturing = true }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.vertical, DGSpace.s3)
                    .background(.ultraThinMaterial)
            }
        }
        .task { refresh() }
        .onChange(of: pose) { refresh() }
        .onChange(of: store.changeToken) { refresh() }
        .confirmationDialog(
            "Delete this photo?", isPresented: deleteDialogBinding, titleVisibility: .visible,
            presenting: pendingDelete
        ) { photo in
            Button("Delete Photo", role: .destructive) { delete(photo) }
        } message: { _ in
            Text("This can't be undone.")
        }
        .sheet(isPresented: $isCapturing, onDismiss: refresh) {
            PhotoCaptureView(pose: pose)
        }
        .sheet(isPresented: $isComparing) {
            PhotoCompareView(pose: pose, photos: photos)
        }
    }

    private var poseChips: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(ProgressPhotoPose.allCases) { candidate in
                DGChip(title: candidate.label.uppercased(), selected: pose == candidate) {
                    pose = candidate
                }
            }
        }
    }

    @ViewBuilder
    private var grid: some View {
        if photos.isEmpty {
            EmptyState(
                symbol: "camera.fill", title: "No \(pose.label) Photos",
                message: "Add a photo to start tracking your \(pose.label.lowercased()) view."
            )
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DGSpace.s3) {
                ForEach(photos) { photo in
                    PhotoGridCell(photo: photo, preferences: preferences)
                        .contextMenu {
                            Button("Delete Photo", systemImage: "trash", role: .destructive) {
                                pendingDelete = photo
                            }
                        }
                }
            }
        }
    }

    private func refresh() {
        photos = store.photos(pose: pose)
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func delete(_ photo: ProgressPhotoInfo) {
        store.deletePhoto(id: photo.id)
        pendingDelete = nil
        refresh()
    }
}

/// One thumbnail cell: image, date and bodyweight caption.
private struct PhotoGridCell: View {
    var photo: ProgressPhotoInfo
    var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            thumbnail
            Text(Self.dateLabel(photo.date))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
            if let kg = photo.bodyweightKg {
                Text(preferences.formatWeight(kg: kg)).dgLabel()
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let data = photo.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(DGColor.surface2)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        let store = WorkoutStore(context: container.mainContext)
        return AnyView(
            ProgressPhotosView()
                .environment(store)
                .environment(Preferences())
        )
    }
    return AnyView(Text("Preview unavailable"))
}
