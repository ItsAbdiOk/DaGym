import PassKit
import SwiftUI
import UIKit

/// Apple's own "Add to Apple Wallet" button — the mark App Review expects, not a lookalike.
struct AddToWalletButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.accessibilityIdentifier = A11yID.walletAdd
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) {
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PKAddPassButton, context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}

/// Wallet's add-pass sheet for one generated pass; `onFinish` fires whether it was added or
/// cancelled, so the caller re-checks the library.
struct AddPassesSheet: UIViewControllerRepresentable {
    var pass: PKPass
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = PKAddPassesViewController(pass: pass) else {
            // `nil` only when passes can't be added at all; the button is hidden in that case.
            return UIViewController()
        }
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    @MainActor
    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        /// The delegate protocol isn't main-actor annotated, but PassKit calls it on the main
        /// thread like every UIKit delegate.
        nonisolated func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            MainActor.assumeIsolated {
                let finish = onFinish
                controller.dismiss(animated: true) { finish() }
            }
        }
    }
}
