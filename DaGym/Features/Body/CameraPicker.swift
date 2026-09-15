import SwiftUI
import UIKit

/// Thin `UIImagePickerController` wrapper for progress-photo capture, with an optional ghost
/// overlay (`cameraOverlayView`) so retaking a shot lines up with the previous one (plan.md
/// §6.4). Hands back the picker's `UIImage` as-is — re-encoding a 12 MP shot to JPEG here would
/// be main-thread work the caller only undoes again. `PhotoCaptureView` is the only caller.
struct CameraPicker: UIViewControllerRepresentable {
    var ghost: UIImage?
    var onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        controller.showsCameraControls = true
        if let ghost {
            // Size to the picker's own view; the overlay resizes with it via autoresizing.
            let overlay = GhostOverlayView(image: ghost, frame: controller.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.cameraOverlayView = overlay
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
                onCapture(image)
            }
        }
    }
}

/// A previous photo drawn at 35% opacity over the live camera preview, for consistent framing
/// between progress-photo shots. Non-interactive, so touches fall through to the picker's own
/// shutter and controls underneath.
private final class GhostOverlayView: UIView {
    private let imageView: UIImageView

    init(image: UIImage, frame: CGRect) {
        imageView = UIImageView(image: image)
        super.init(frame: frame)
        imageView.frame = frame
        imageView.contentMode = .scaleAspectFill
        imageView.alpha = 0.35
        imageView.isUserInteractionEnabled = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }
}
