import OSLog
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private let photoLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "photos")

/// Captures a new progress photo for `pose` — camera (`CameraPicker`, ghost-overlaid with the
/// previous photo of this pose for consistent framing) or an existing photo via `PhotosPicker`
/// (plan.md §6.4). The capture is decoded once, off-main, into `capturedImage`; Save downscales
/// it on a detached task (`PhotoProcessor`) before `WorkoutStore.addPhoto` writes the row.
struct PhotoCaptureView: View {
    var pose: ProgressPhotoPose

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var capturedImage: UIImage?
    @State private var bodyweightText = ""
    @State private var isSaving = false
    @FocusState private var bodyweightFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                content
            }
            .navigationTitle("Add \(pose.label) Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker(ghost: ghostImage) { image in
                isCameraPresented = false
                Task { capturedImage = await PhotoDecoder.prepareForDisplay(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickedItem) { _, newItem in
            Task {
                let data = try? await newItem?.loadTransferable(type: Data.self)
                capturedImage = await PhotoDecoder.decodeForDisplay(data)
            }
        }
    }

    private var ghostImage: UIImage? {
        guard let data = store.latestPhoto(pose: pose)?.imageData else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private var content: some View {
        if let capturedImage {
            reviewForm(uiImage: capturedImage)
        } else {
            captureOptions
        }
    }

    private var captureOptions: some View {
        VStack(spacing: DGSpace.s4) {
            Spacer()
            EmptyState(
                symbol: "camera.fill", title: "Add A Photo",
                message: "Use the camera for a consistent, ghost-aligned shot, or pick an existing photo."
            )
            DGPrimaryButton(title: "Open Camera", symbol: "camera.fill") { isCameraPresented = true }
                .padding(.horizontal, DGSpace.s4)
            libraryButton
            Spacer()
        }
    }

    private var libraryButton: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            LibraryButtonLabel()
        }
        .padding(.horizontal, DGSpace.s4)
    }

    private func reviewForm(uiImage: UIImage) -> some View {
        VStack(spacing: DGSpace.s5) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
            bodyweightField
            Spacer()
            reviewActions(uiImage: uiImage)
        }
    }

    private var bodyweightField: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Bodyweight (optional)").dgLabel()
            TextField("e.g. 81.4", text: $bodyweightText)
                .keyboardType(.decimalPad)
                .focused($bodyweightFocused)
                // A decimal pad has no return key, so this is the only way to put the
                // keyboard away without committing the photo.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { bodyweightFocused = false }
                    }
                }
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .padding(DGSpace.s3)
                .background(
                    DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                )
        }
        .padding(.horizontal, DGSpace.s4)
    }

    private func reviewActions(uiImage: UIImage) -> some View {
        HStack(spacing: DGSpace.s3) {
            Button {
                capturedImage = nil
            } label: {
                Text("Retake")
                    .font(DGFont.condensedLabel(15))
                    .foregroundStyle(DGColor.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .dgGlass(.regular, radius: DGRadius.lg)
            }
            .buttonStyle(.dgControl)
            DGPrimaryButton(title: isSaving ? "Saving…" : "Save", symbol: "checkmark") {
                Task { await save(uiImage) }
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s4)
    }

    /// Downscales on a detached task so the 12 MP → 1600 px resize never blocks the tap, then
    /// hands the already-storage-sized JPEG to `addPhoto`. `addPhoto` still runs its own
    /// (cheap, 1600 px) pass on main — an `addPhoto(processed:)` overload would remove it.
    private func save(_ uiImage: UIImage) async {
        isSaving = true
        defer { isSaving = false }
        let entered = Double(bodyweightText.replacingOccurrences(of: ",", with: "."))
        let bodyweightKg = entered.map { preferences.weightUnit.toKg($0) }
        let processed = await Task.detached(priority: .userInitiated) {
            PhotoProcessor.process(uiImage)
        }.value
        guard let processed else {
            photoLogger.error("PhotoProcessor returned nil for a \(Int(uiImage.size.width))px capture")
            return
        }
        store.addPhoto(processed: processed, pose: pose, bodyweightKg: bodyweightKg)
        Haptics.confirm()
        dismiss()
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        let store = WorkoutStore(context: container.mainContext)
        return AnyView(
            PhotoCaptureView(pose: .front)
                .environment(store)
                .environment(Preferences())
        )
    }
    return AnyView(Text("Preview unavailable"))
}

/// Standalone label type: `PhotosPicker`'s label closure is not main-actor isolated, so it
/// cannot reference view-isolated helpers directly.
private struct LibraryButtonLabel: View {
    var body: some View {
        Text("Choose From Library")
            .font(DGFont.condensedLabel(15))
            .foregroundStyle(DGColor.ink1)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .dgGlass(.regular, radius: DGRadius.lg)
    }
}
