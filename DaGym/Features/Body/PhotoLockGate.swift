import LocalAuthentication
import SwiftUI

/// Face ID gate in front of the progress-photos grid (`preferences.lockPhotos`, plan.md §6.4).
/// Shows a lock screen until biometric (or passcode) auth succeeds; falls straight through when
/// the preference is off, and never hard-locks a device with no biometrics enrolled.
struct PhotoLockGate<Content: View>: View {
    @Environment(Preferences.self) private var preferences

    @State private var isUnlocked = false
    @State private var didFail = false

    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if !preferences.lockPhotos || isUnlocked {
                content()
            } else {
                lockScreen
            }
        }
        .task(id: preferences.lockPhotos) {
            if preferences.lockPhotos && !isUnlocked { authenticate() }
        }
    }

    private var lockScreen: some View {
        ZStack {
            AmbientWash()
            EmptyState(
                symbol: "faceid",
                title: "Locked",
                message: didFail
                    ? "Face ID failed. Try again to view your progress photos."
                    : "Progress photos are locked with Face ID.",
                action: "Unlock", onAction: authenticate
            )
            .padding(.horizontal, DGSpace.s4)
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode set up on this device — don't lock the user out.
            isUnlocked = true
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: "Unlock your progress photos"
        ) { success, _ in
            Task { @MainActor in
                isUnlocked = success
                didFail = !success
            }
        }
    }
}

#Preview {
    PhotoLockGate {
        Text("Unlocked content")
    }
    .environment(Preferences())
}
