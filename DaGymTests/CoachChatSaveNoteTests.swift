import Foundation
import GymCore
import Testing

@testable import DaGym

/// Long-press "Save as note" and "Remember this": which targets a reply offers, what each
/// writes through the store or the memory file, and the words the menu and toast use.
@MainActor
@Suite("Coach chat save as note")
struct CoachChatSaveNoteTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func save(
        _ target: CoachChatSaveTarget, _ fixture: CoachChatToolFixture, memory: CoachMemoryFile? = nil,
        threadID: UUID? = nil, at date: Date? = nil
    ) -> Bool {
        CoachChatSaver.save(
            target, store: fixture.store, memory: memory, threadID: threadID, now: date ?? day
        )
    }

    @Test("a reply naming two exercises offers a note for each, in order, then Remember this")
    func twoExercisesNamed() throws {
        let fixture = try CoachChatToolFixture.make()
        let reply = "Keep the **Dumbbell Row** strict.\n\n- Bench Press stays at 80 kg\n- Rest 2 min"
        let targets = CoachChatSaveTargets.forReply(reply, library: fixture.store.substitutionCandidates())
        #expect(targets.map(\.menuLabel) == [
            "Save as note for Dumbbell Row", "Save as note for Bench Press", "Remember this"
        ])
        #expect(targets.map(\.toast) == [
            "Saved to Dumbbell Row notes", "Saved to Bench Press notes", "Remembered"
        ])
        #expect(targets.map(\.accessibilityLabel) == [
            "Save as note for Dumbbell Row, shown on its card in every workout",
            "Save as note for Bench Press, shown on its card in every workout",
            "Remember this in coach memory"
        ])
        guard case .exerciseNote(let id, _, let note) = targets[0] else {
            Issue.record("expected an exercise note")
            return
        }
        #expect(id == fixture.row.id)
        // Markdown markers are gone from the note; list items read as bullets.
        #expect(note == "Coach: Keep the Dumbbell Row strict. • Bench Press stays at 80 kg • Rest 2 min")
        #expect(CoachChatSaveTargets.forReply("   ", library: []).isEmpty)
        let plain = CoachChatSaveTargets.forReply("No exercise here.", library: [])
        #expect(plain.map(\.menuLabel) == ["Remember this"])
    }

    @Test("an exercise the gym cannot do is still offered, and saving it is an always note on the card")
    func unavailableExerciseNote() throws {
        let fixture = try CoachChatToolFixture.make()
        let targets = CoachChatSaveTargets.forReply(
            "Skip the Leg Press until the knee settles.", library: fixture.store.substitutionCandidates()
        )
        let target = try #require(targets.first)
        #expect(target.menuLabel == "Save as note for Leg Press")
        #expect(save(target, fixture))
        let pinned = try #require(fixture.store.pinnedNote(exerciseID: fixture.legPress.id))
        #expect(pinned.scope == .always)
        #expect(pinned.text == "Coach: Skip the Leg Press until the knee settles.")
    }

    @Test("saving the same reply twice leaves one note; a different reply adds a second")
    func duplicateSave() throws {
        let fixture = try CoachChatToolFixture.make()
        let target = CoachChatSaveTarget.exerciseNote(
            exerciseID: fixture.bench.id, exerciseName: "Bench Press", note: "Coach: Pause on the chest."
        )
        #expect(save(target, fixture))
        #expect(save(target, fixture, at: day + 60))
        let notes = fixture.store.exerciseNotes(exerciseID: fixture.bench.id)
        #expect(notes.map(\.text) == ["Coach: Pause on the chest."])
        let other = CoachChatSaveTarget.exerciseNote(
            exerciseID: fixture.bench.id, exerciseName: "Bench Press", note: "Coach: Tuck the elbows."
        )
        #expect(save(other, fixture, at: day + 120))
        #expect(fixture.store.exerciseNotes(exerciseID: fixture.bench.id).count == 2)
    }

    @Test("Remember this files the gist under Other with the thread as source; no memory file saves nothing")
    func remember() throws {
        let fixture = try CoachChatToolFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.memory.fileURL.deletingLastPathComponent()) }
        let thread = UUID()
        let tail = String(repeating: "x", count: 200)
        let reply = "Your bench is stalling at 80 kg. Deload 10% next week. " + tail
        let target = try #require(
            CoachChatSaveTargets.forReply(reply, library: []).first { $0.menuLabel == "Remember this" }
        )
        #expect(save(target, fixture, memory: fixture.memory, threadID: thread))
        let facts = fixture.memory.facts()
        #expect(facts.count == 1)
        #expect(facts.first?.text == "Your bench is stalling at 80 kg. Deload 10% next week.")
        #expect(facts.first?.topic == .other)
        #expect(facts.first?.sourceThreadID == thread)
        #expect(!save(target, fixture, memory: nil, threadID: thread))
    }

    @Test("memory keeps sixty facts, newest first, so a sixty-first remembered fact pushes out the oldest")
    func memoryCap() throws {
        let fixture = try CoachChatToolFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.memory.fileURL.deletingLastPathComponent()) }
        let old = (0..<CoachMemoryValidation.maxFacts).map { index in
            CoachMemoryFact(text: "Fact \(index)", topic: .other, createdAt: day - Double(index) * 60)
        }
        try fixture.memory.replaceAll(old)
        #expect(save(.remember(gist: "Newest fact"), fixture, memory: fixture.memory, at: day + 60))
        let facts = fixture.memory.facts()
        #expect(facts.count == CoachMemoryValidation.maxFacts)
        #expect(facts.first?.text == "Newest fact")
        #expect(!facts.contains { $0.text == "Fact \(CoachMemoryValidation.maxFacts - 1)" })
    }

    @Test("a draft card offers a note per exercise with a reason, or the changed exercise on a deload")
    func draftTargets() {
        let bench = UUID()
        let row = UUID()
        let routine = RoutineProposal(
            name: "Upper", exercises: [
                CoachChatExerciseSpec(
                    exerciseID: bench, exerciseName: "Bench Press", sets: [CoachChatSetSpec(targetReps: 8)],
                    reason: "Your strongest press."
                ),
                CoachChatExerciseSpec(
                    exerciseID: row, exerciseName: "Dumbbell Row", sets: [CoachChatSetSpec(targetReps: 10)]
                )
            ]
        )
        let targets = CoachChatSaveTargets.forDraft(.routine(routine))
        #expect(targets == [
            .exerciseNote(
                exerciseID: bench, exerciseName: "Bench Press", note: "Coach: Your strongest press."
            )
        ])
        let deload = DeloadProposal(exerciseID: bench, exerciseName: "Bench Press", percent: 10)
        let deloadTargets = CoachChatSaveTargets.forDraft(.deload(deload))
        #expect(deloadTargets.map(\.menuLabel) == ["Save as note for Bench Press"])
        #expect(CoachChatSaveTargets.forDraft(.schedule(ScheduleProposal(days: [:]))).isEmpty)
    }

    @Test("keeping the reasoning writes the routine note and each exercise's reason; undo takes it all")
    func routineNoteFromReasoning() async throws {
        let fixture = try CoachChatToolFixture.make()
        let json = """
        {"name":"Pull","notes":"Rows first.","exercises":[
          {"exercise_name":"Dumbbell Row","sets":[{"target_reps":10}],"reason":"Your lats are behind."},
          {"exercise_name":"Bench Press","sets":[{"target_reps":6}]}
        ]}
        """
        let draft = try await fixture.draft(.proposeRoutine, json)
        let reasoning = "  Rows lead because your lats lag your pressing.\n\nBench closes the day.  "
        let application = try fixture.store.apply(draft, reasoning: reasoning)
        guard case .routine(let id, _) = application else {
            Issue.record("expected a routine application")
            return
        }
        let expected = "Rows first.\n\nRows lead because your lats lag your pressing.\n\n"
            + "Bench closes the day."
        #expect(fixture.store.fetchRoutineModel(id: id)?.notes == expected)
        let (_, drafts) = try #require(fixture.store.routineDrafts(id: id))
        #expect(drafts.map(\.note) == ["Your lats are behind.", ""])
        fixture.store.undo(application)
        #expect(fixture.store.fetchRoutineModel(id: id) == nil)

        // Switch off: the proposal's own notes only, no reasons on the slots.
        let plain = try fixture.store.apply(draft)
        guard case .routine(let plainID, _) = plain else {
            Issue.record("expected a routine application")
            return
        }
        #expect(fixture.store.fetchRoutineModel(id: plainID)?.notes == "Rows first.")
        let (_, plainDrafts) = try #require(fixture.store.routineDrafts(id: plainID))
        #expect(plainDrafts.map(\.note) == ["", ""])

        // A very long reply is cut so the routine note stays a card, not a page.
        let long = String(repeating: "a", count: 1_500)
        let cut = WorkoutStore.routineNotes(nil, reasoning: long)
        #expect(cut.count == WorkoutStore.maxReasoningLength)
        #expect(cut.hasSuffix("…"))
        #expect(WorkoutStore.routineNotes("Own.", reasoning: "   ") == "Own.")
    }

    @Test("the reasoning for a card is the reply after it in the turn, else the words before it")
    func reasoningLookup() {
        let messages: [CoachChatMessage] = [
            .user("Plan my upper day", at: day),
            .assistant("Here is a **plan**.", at: day),
            .tool("propose_routine", at: day),
            .draft(index: 0, summary: "Upper", at: day),
            .assistant("", at: day),
            .assistant("Bench leads because it is your strongest press.", at: day),
            .user("Thanks", at: day),
            .assistant("Any time.", at: day)
        ]
        let after = CoachChatTranscript.reasoning(forDraftAt: 0, in: messages)
        #expect(after == "Bench leads because it is your strongest press.")
        let before = CoachChatTranscript.reasoning(forDraftAt: 0, in: Array(messages.prefix(4)))
        #expect(before == "Here is a plan.")
        #expect(CoachChatTranscript.reasoning(forDraftAt: 1, in: messages) == nil)
        let silent: [CoachChatMessage] = [.user("Go", at: day), .draft(index: 0, summary: "Upper", at: day)]
        #expect(CoachChatTranscript.reasoning(forDraftAt: 0, in: silent) == nil)
    }

    @Test("the save-target cache scans once per message, again when its text changes, and forgets on reset")
    func targetCacheKeys() throws {
        let fixture = try CoachChatToolFixture.make()
        let library = fixture.store.substitutionCandidates()
        let cache = CoachChatSaveTargetCache()
        var reply = CoachChatMessage.assistant("Keep the Bench Press strict.", at: day)
        let first = cache.targets(for: reply, library: library)
        #expect(first.map(\.menuLabel) == ["Save as note for Bench Press", "Remember this"])
        #expect(cache.targets(for: reply, library: library) == first)
        #expect(cache.scanCount == 1)

        // The same bubble while its reply is still streaming: new text, new scan.
        reply.text += " Then Dumbbell Row."
        #expect(cache.targets(for: reply, library: library).map(\.menuLabel) == [
            "Save as note for Bench Press", "Save as note for Dumbbell Row", "Remember this"
        ])
        #expect(cache.scanCount == 2)
        #expect(cache.targets(for: reply, library: library).count == 3)
        #expect(cache.scanCount == 2)

        // A different message with the same words is its own entry.
        let other = CoachChatMessage.assistant(reply.text, at: day)
        #expect(cache.targets(for: other, library: library).count == 3)
        #expect(cache.scanCount == 3)

        // Reset (the library was re-read) drops everything.
        cache.reset()
        #expect(cache.targets(for: reply, library: []).map(\.menuLabel) == ["Remember this"])
        #expect(cache.scanCount == 4)
    }
}
