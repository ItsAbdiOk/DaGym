import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Captures a new progress photo for `pose` — camera (`CameraPicker`, ghost-overlaid with the
/// previous photo of this pose for consistent framing) or an existing photo via `PhotosPicker`
/// (plan.md §6.4). Saves through `WorkoutStore.addPhoto` and dismisses.
struct PhotoCaptureView: View {
    var pose: ProgressPhotoPose

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var capturedData: Data?
    @State private var bodyweightText = ""

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
            CameraPicker(ghost: ghostImage) { data in
                capturedData = data
                isCameraPresented = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickedItem) { _, newItem in
            Task { capturedData = try? await newItem?.loadTransferable(type: Data.self) }
        }
    }

    private var ghostImage: UIImage? {
        guard let data = store.latestPhoto(pose: pose)?.imageData else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private var content: some View {
        if let capturedData, let uiImage = UIImage(data: capturedData) {
            reviewForm(uiImage: uiImage, data: capturedData)
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

    private func reviewForm(uiImage: UIImage, data: Data) -> some View {
        VStack(spacing: DGSpace.s5) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
            bodyweightField
            Spacer()
            reviewActions(data: data)
        }
    }

    private var bodyweightField: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Bodyweight (optional)").dgLabel()
            TextField("e.g. 81.4", text: $bodyweightText)
                .keyboardType(.decimalPad)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .padding(DGSpace.s3)
                .background(
                    DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                )
        }
        .padding(.horizontal, DGSpace.s4)
    }

    private func reviewActions(data: Data) -> some View {
        HStack(spacing: DGSpace.s3) {
            Button {
                capturedData = nil
            } label: {
                Text("Retake")
                    .font(DGFont.condensedLabel(15))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .dgGlass(.regular, radius: DGRadius.lg)
            }
            .buttonStyle(DGPressStyle())
            DGPrimaryButton(title: "Save", symbol: "checkmark") { save(data: data) }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s4)
    }

    private func save(data: Data) {
        let entered = Double(bodyweightText.replacingOccurrences(of: ",", with: "."))
        let bodyweightKg = entered.map { preferences.weightUnit.toKg($0) }
        store.addPhoto(image: data, pose: pose, bodyweightKg: bodyweightKg)
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
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.ink1)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .dgGlass(.regular, radius: DGRadius.lg)
    }
}
