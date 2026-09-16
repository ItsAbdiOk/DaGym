import Foundation
import GymCore
import Testing

@testable import DaGym

/// The canned coach chat behind the `coachChat` / `coachReview` screenshots must stay a thread
/// the real screen can render: every draft passes `CoachChatDraft.validate` against the seed
/// library and the stock equipment, unchanged (so the card shows what the store would save),
/// and the thread survives the archive round trip the screen loads it through.
@MainActor
@Suite("Screenshot coach chat fixture")
struct ScreenshotCoachChatTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("every draft validates against the seed library without changing")
    func draftsValidate() throws {
        let store = try makeStore(seed: .stocked)
        let availability = store.equipmentAvailabilityForProgram()
        let library = store.substitutionCandidates()
        for draft in ScreenshotCoachChat.drafts {
            switch draft.validate(availability: availability, library: library) {
            case .success(let validated):
                guard case .routine(let original) = draft, case .routine(let accepted) = validated else {
                    Issue.record("expected routine drafts")
                    return
                }
                #expect(accepted.name == original.name)
                #expect(accepted.notes == original.notes)
                #expect(accepted.exercises.map(\.exerciseName) == original.exercises.map(\.exerciseName))
                #expect(accepted.exercises.map(\.reason) == original.exercises.map(\.reason))
                #expect(accepted.exercises.allSatisfy { $0.exerciseID != nil })
                #expect(accepted.exercises.allSatisfy { $0.reason?.isEmpty == false })
            case .failure(let rejection):
                Issue.record("\(draft.summary) rejected: \(rejection.reasons.joined(separator: "; "))")
            }
        }
    }

    @Test("both threads point their cards and reviews at drafts that exist, and round-trip the archive")
    func threadsAreConsistent() throws {
        let archive = CoachChatArchive(
            directory: FileManager.default.temporaryDirectory.appending(path: "shots-\(UUID().uuidString)")
        )
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let threads = [
            ScreenshotCoachChat.chatThread(now: Self.now), ScreenshotCoachChat.reviewThread(now: Self.now)
        ]
        for thread in threads {
            #expect(thread.messages.first?.role == .user)
            #expect(thread.messages.first?.text == ScreenshotCoachChat.question)
            #expect(thread.drafts.count == thread.draftOrigins.count)
            let cardIndices = thread.messages.compactMap { $0.role == .draft ? $0.draftIndex : nil }
            #expect(cardIndices == Array(thread.drafts.indices))
            for review in thread.reviews {
                #expect(thread.drafts.indices.contains(review.draftIndex))
                if let alternative = review.alternativeDraftIndex {
                    #expect(thread.drafts.indices.contains(alternative))
                    #expect(thread.origin(ofDraft: alternative) == .reviewer)
                }
            }
            #expect(thread.messages.contains { $0.role == .assistant && $0.text.contains("**") })
            #expect(!CoachChatTranscript.isWaitingForText(thread.messages))
            try archive.save(thread)
            #expect(archive.load(id: thread.id) == thread)
        }
        let chat = ScreenshotCoachChat.chatThread(now: Self.now)
        #expect(chat.drafts.count == 1)
        #expect(chat.reviews.isEmpty)
        let review = ScreenshotCoachChat.reviewThread(now: Self.now)
        #expect(review.drafts.count == 2)
        #expect(review.messages.last?.role == .draft)
        #expect(CoachDraftLinks.linkedDraftIndex(for: 0, in: review.reviews) == 1)
        let rationale = CoachDraftLinks.rationale(for: 1, in: review.reviews)
        #expect(rationale == ScreenshotCoachChat.alternativeRationale)
    }
}
