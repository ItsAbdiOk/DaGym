import SwiftUI

// PLACEHOLDER STYLING — see `VoiceReviewCard`'s header comment. The listening banner and error
// alert here are the same "clean, on-system, not final" deal.

/// The active-workout entry point for voice logging: the hold-to-talk button, the live partial
/// transcript while held, the "what I understood" card, and error states. Mount once per
/// `ActiveWorkoutView` — it owns its own `VoiceLogController` and reuses the screen's existing
/// `UndoAction` toast (`undoAction`) so a voice-logged set undoes exactly like any other set.
struct VoiceLogEntryPoint: View {
    var session: WorkoutSession
    var store: WorkoutStore
    var preferences: Preferences
    @Binding var undoAction: UndoAction?

    @State private var controller = VoiceLogController(
        recognizer: OnDeviceSpeechRecognizer(), speaker: VoiceSpeechSynthesizer()
    )
    @State private var reviewCard: VoiceLogController.ReviewCard?
    @State private var activeError: VoiceLogController.VoiceLogError?

    var body: some View {
        HoldToTalkButton(
            isListening: isListening,
            onPressDown: { controller.startHolding() },
            onRelease: {
                controller.stopHolding(session: session, store: store, preferences: preferences) { action in
                    undoAction = action
                }
            }
        )
        .overlay(alignment: .top) {
            if case .listening(let partial) = controller.state {
                VoiceListeningOverlay(partialTranscript: partial)
                    .frame(width: 240)
                    .offset(y: 62)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(DGMotion.standard, value: controller.state)
        .sheet(item: $reviewCard) { card in
            reviewSheet(for: card)
        }
        .onChange(of: controller.state) { _, newState in sync(newState) }
        .onDisappear { controller.cancel() }
        .alert(
            title(for: activeError), isPresented: Binding(
                get: { activeError != nil }, set: { if !$0 { activeError = nil } }
            )
        ) {
            Button("OK") { activeError = nil }
        } message: {
            Text(activeError.map(message(for:)) ?? "")
        }
    }

    private var isListening: Bool {
        if case .listening = controller.state { return true }
        return false
    }

    private func sync(_ state: VoiceLogController.State) {
        switch state {
        case .reviewing(let card):
            reviewCard = card
        case .error(let error):
            reviewCard = nil
            activeError = error
        default:
            reviewCard = nil
        }
    }

    @ViewBuilder
    private func reviewSheet(for card: VoiceLogController.ReviewCard) -> some View {
        VoiceReviewCard(
            card: Binding(get: { reviewCard ?? card }, set: { reviewCard = $0 }),
            onLog: {
                guard let current = reviewCard else { return }
                controller.confirmReview(current, session: session, store: store) { action in
                    undoAction = action
                }
            },
            onDismiss: {
                controller.dismissReview()
                reviewCard = nil
            }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .padding(DGSpace.s4)
    }

    private func title(for error: VoiceLogController.VoiceLogError?) -> String {
        guard let error else { return "" }
        switch error {
        case .permissionDenied: return "Microphone access needed"
        case .onDeviceUnavailable: return "Voice logging unavailable"
        case .nothingHeard: return "Didn't catch that"
        case .didNotUnderstand: return "Didn't understand"
        case .exerciseNotInSession: return "Not in today's workout"
        case .needsDisambiguation: return "Which exercise?"
        case .unsupportedCommand: return "Not supported yet"
        case .audioFailure: return "Voice logging hiccuped"
        }
    }

    private func message(for error: VoiceLogController.VoiceLogError) -> String {
        switch error {
        case .permissionDenied:
            return "Turn on Speech Recognition and Microphone access for DaGym in Settings to log sets " +
                "by voice."
        case .onDeviceUnavailable:
            return "On-device speech recognition isn't available right now — voice logging never sends " +
                "audio off your phone, so it can't fall back to the network. Try again in a moment."
        case .nothingHeard:
            return "No speech came through. Hold the mic button and speak while it's held."
        case .didNotUnderstand:
            return "Try something like \u{201C}two twenty-five for eight.\u{201D}"
        case .exerciseNotInSession(let spoken):
            return spoken.isEmpty
                ? "That exercise isn't in today's workout."
                : "\u{201C}\(spoken)\u{201D} isn't in today's workout."
        case .needsDisambiguation(let spoken, let candidates):
            let list = candidates.prefix(3).joined(separator: ", ")
            return spoken.isEmpty
                ? "Could be \(list) — say the full name to log it."
                : "\u{201C}\(spoken)\u{201D} could mean \(list) — say the full name to log it."
        case .unsupportedCommand:
            return "That kind of voice command isn't wired up yet — try logging a weight and rep count."
        case .audioFailure:
            return "Something went wrong with the microphone. Try again."
        }
    }
}
