import GymCore
import SwiftUI

/// Screen 4. watchOS has no Speech framework, so 4A "Listening" is the system dictation sheet
/// (`TextFieldLink`): the transcript is typed by the system, on device, and handed back here.
/// 4B "Heard you" shows the parsed values with Log and Fix — nothing commits without one of
/// those taps.
struct VoiceLogView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var parsed: WatchVoiceParse?
    @State private var failedPhrase: String?

    var body: some View {
        VStack(spacing: 6) {
            if let parsed {
                confirm(parsed)
            } else {
                listen
            }
        }
        .padding(.horizontal, WatchMetric.gutter)
        .onAppear { if let seeded = store.debugVoiceParse { parsed = seeded } }
    }

    private var listen: some View {
        VStack(spacing: 8) {
            SafeBandText(text: "Listening", font: WatchFont.title, color: WatchColor.ink)
            Spacer()
            Image(systemName: "mic.fill").font(.system(size: 28)).foregroundStyle(WatchColor.voice)
            Text(failedPhrase.map { "“\($0)”" } ?? "Say the set: “did eight at a hundred”")
                .font(WatchFont.body)
                .foregroundStyle(failedPhrase == nil ? WatchColor.inkSecondary : WatchColor.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if failedPhrase != nil {
                Text("Couldn't log that").font(WatchFont.secondary).foregroundStyle(WatchColor.inkSecondary)
            }
            Spacer()
            TextFieldLink(prompt: Text("Log a set")) {
                Text("Speak")
                    .font(WatchFont.button)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: WatchMetric.capsule)
                    .background(Capsule().fill(WatchColor.voice))
            } onSubmit: { phrase in handle(phrase) }
            .buttonStyle(.plain)
            Button("Cancel") { dismiss() }
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.inkSecondary)
                .buttonStyle(.plain)
                .frame(height: WatchMetric.safeBand)
        }
    }

    private func confirm(_ parsed: WatchVoiceParse) -> some View {
        let unit = preferences.weightUnit
        return VStack(spacing: 4) {
            SafeBandText(text: "Heard you", font: WatchFont.title, color: WatchColor.voice)
            Text("“\(parsed.phrase)”")
                .font(WatchFont.secondary)
                .foregroundStyle(WatchColor.inkSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
            Text("\(parsed.exerciseName) · set \(parsed.setNumber)")
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.ink)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(unit.format(kg: parsed.weightKg ?? 0)).font(WatchFont.value(30))
                Text("\(unit.symbol) ×").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                Text("\(parsed.reps ?? 0)").font(WatchFont.value(30))
                if let effort = parsed.effort {
                    Text("RPE \(effort.displayValue(scale: .rpe))")
                        .font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                }
            }
            .foregroundStyle(WatchColor.ink)
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                CapsuleButton(title: "Log", tint: WatchColor.commit) { commit(parsed) }
                CapsuleButton(title: "Fix", tint: WatchColor.card) { load(parsed); dismiss() }
                    .foregroundStyle(WatchColor.ink)
            }
        }
    }

    private func handle(_ phrase: String) {
        guard let session = store.session,
              let result = WatchVoiceLog.parse(
                  phrase, session: session, store: store.store, unit: preferences.weightUnit
              ) else {
            Haptics.invalid()
            failedPhrase = phrase
            return
        }
        parsed = result
    }

    /// Fix: the parsed values go onto the on-deck set without completing it, so a wrong number
    /// costs one crown turn, not a repeat of the phrase.
    private func load(_ parsed: WatchVoiceParse) {
        store.updateSet(exerciseID: parsed.exerciseID) { set in
            if let kg = parsed.weightKg { set.weightKg = kg }
            if let reps = parsed.reps { set.reps = reps }
            if let effort = parsed.effort { set.effort = effort }
            if let seconds = parsed.durationSeconds { set.durationSeconds = seconds }
        }
        if let index = store.session?.exercises.firstIndex(where: { $0.id == parsed.exerciseID }) {
            store.pageIndex = index
        }
    }

    private func commit(_ parsed: WatchVoiceParse) {
        load(parsed)
        store.logCurrentSet(exerciseID: parsed.exerciseID, effort: parsed.effort)
        dismiss()
    }
}
