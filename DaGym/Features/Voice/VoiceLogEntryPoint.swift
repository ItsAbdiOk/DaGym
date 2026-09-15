import SwiftUI

// PLACEHOLDER STYLING — see `VoiceReviewCard`'s header comment. The listening banner and error
// alert here are the same "clean, on-system, not final" deal. The error *copy* is not
// placeholder: each string is the only thing telling a user what to do next.

/// The active-workout entry point for voice logging: the hold-to-talk button, the live partial
/// transcript while held, the "what I understood" card, and error states. Mount once per
/// `ActiveWorkoutView`, which owns the `VoiceLogController` (built once in its `onAppear`) and
/// passes it in — a `@State` initial value here was re-evaluated on every construction of this
/// struct, i.e. every header render, allocating and discarding an `SFSpeechRecognizer`, an
/// `AVAudioEngine` and a synthesizer per rest tick. It reuses the screen's existing `UndoAction`
/// toast (`undoAction`) so a voice-logged set undoes exactly like any other set.
struct VoiceLogEntryPoint: View {
    var session: WorkoutSession
    var store: WorkoutStore
    var preferences: Preferences
    var controller: VoiceLogController
    @Binding var undoAction: UndoAction?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var reviewCard: VoiceLogController.ReviewCard?
    @State private var activeError: VoiceLogController.VoiceLogError?

    var body: some View {
        HoldToTalkButton(
            isListening: isListening,
            onPressDown: { controller.startHolding() },
            // Release is async: it stops the mic and waits briefly for the recognizer's final
            // hypothesis rather than acting on the truncated partial that happened to be on
            // screen when the finger lifted.
            onRelease: {
                Task {
                    await controller.stopHolding(
                        session: session, store: store, preferences: preferences
                    ) { action in
                        undoAction = action
                    }
                }
            }
        )
        .overlay(alignment: .top) {
            if case .listening(let partial) = controller.state {
                VoiceListeningOverlay(partialTranscript: partial)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 340 : 240)
                    .offset(y: 62)
                    .dgTransition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .dgAnimation(DGMotion.standard, value: controller.state)
        .sheet(item: $reviewCard) { card in
            reviewSheet(for: card)
        }
        .onChange(of: controller.state) { _, newState in sync(newState) }
        .onDisappear { controller.cancel() }
        .alert(
            activeError.map(title(for:)) ?? "", isPresented: Binding(
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
                controller.confirmReview(
                    current, session: session, store: store, preferences: preferences
                ) { action in
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

    private func title(for error: VoiceLogController.VoiceLogError) -> String {
        switch error {
        case .permissionDenied: return "Microphone access needed"
        case .permissionRestricted: return "Voice logging is restricted"
        case .onDeviceUnavailable: return "Voice logging unavailable"
        case .nothingHeard: return "Didn't catch that"
        case .didNotUnderstand: return "Didn't understand"
        case .exerciseNotInSession: return "Not in today's workout"
        case .needsDisambiguation: return "Which exercise?"
        case .unsupportedCommand: return "Not supported yet"
        case .valueOutOfRange: return "Check those numbers"
        case .audioFailure: return "Voice logging hiccuped"
        }
    }

    /// Split in two only to stay under the cyclomatic-complexity cap — `setupMessage` covers the
    /// states the user fixes outside the app (permission, hardware), `parseMessage` the ones they
    /// fix by saying or typing something different.
    private func message(for error: VoiceLogController.VoiceLogError) -> String {
        setupMessage(for: error) ?? parseMessage(for: error)
    }

    private func setupMessage(for error: VoiceLogController.VoiceLogError) -> String? {
        switch error {
        case .permissionDenied:
            return "Turn on Speech Recognition and Microphone access for DaGym in Settings to log " +
                "sets by voice."
        case .permissionRestricted:
            // Screen Time or an MDM profile: there is no switch this user can flip, so sending
            // them to Settings would be a dead end.
            return "Speech recognition is blocked on this device by Screen Time or a device " +
                "management profile. Whoever manages those restrictions has to allow it — until " +
                "then, log sets by tapping them in."
        case .onDeviceUnavailable:
            return "On-device speech recognition isn't available right now — voice logging never " +
                "sends audio off your phone, so it can't fall back to the network. Try again in " +
                "a moment."
        case .audioFailure:
            return "Something went wrong with the microphone. Try again."
        default:
            return nil
        }
    }

    private func parseMessage(for error: VoiceLogController.VoiceLogError) -> String {
        switch error {
        case .nothingHeard:
            return "No speech came through. Hold the mic button and speak while it's held."
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
        case .valueOutOfRange:
            return "Those numbers are outside what a set can hold. Check the weight and reps and " +
                "try again."
        default:
            return "Try something like \u{201C}two twenty-five for eight.\u{201D}"
        }
    }
}
