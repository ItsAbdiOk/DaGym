import Foundation
import Testing

@testable import DaGym

@Suite("WorkoutPresentation: the shell's minimise / resume / finish state")
@MainActor
struct WorkoutPresentationTests {
    private func session(_ title: String = "Push A") -> WorkoutSession {
        WorkoutSession(title: title, subtitle: "", startedAt: Date(), exercises: [])
    }

    @Test("empty: nothing presented, no resume bar, and minimise / resume / finish are no-ops")
    func empty() {
        var state = WorkoutPresentation()
        #expect(state.session == nil)
        #expect(state.presented == nil)
        #expect(!state.showsResumeBar)
        state.minimise()
        #expect(!state.isMinimised)
        state.resume()
        #expect(state.finish() == nil)
        #expect(state.session == nil)
    }

    @Test("present puts the session on screen; minimise keeps it alive with the cover down")
    func presentThenMinimise() {
        var state = WorkoutPresentation()
        let live = session()
        state.present(live)
        #expect(state.presented === live)
        #expect(!state.showsResumeBar)

        state.minimise()
        #expect(state.session === live, "minimising must not lose the session")
        #expect(state.presented == nil, "the cover binds to nil while minimised")
        #expect(state.showsResumeBar)

        state.resume()
        #expect(state.presented === live)
        #expect(!state.showsResumeBar)
    }

    @Test("finish clears both and hands back the session it cleared, minimised or not")
    func finish() {
        var state = WorkoutPresentation()
        let live = session("Legs")
        state.present(live)
        state.minimise()
        #expect(state.finish() === live)
        #expect(state.session == nil)
        #expect(!state.isMinimised)
        #expect(!state.showsResumeBar)
    }

    @Test("presenting over a minimised session replaces it and puts the cover up")
    func presentReplaces() {
        var state = WorkoutPresentation()
        state.present(session("First"))
        state.minimise()
        let second = session("Second")
        state.present(second)
        #expect(state.presented === second)
        #expect(!state.isMinimised)
    }
}
