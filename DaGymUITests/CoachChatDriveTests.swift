import XCTest

// A driver a human reads from the xcodebuild log, not app code.
// swiftlint:disable no_print_statements

/// Drives a real coach conversation against OpenRouter from the simulator, for a human to read
/// the trace of. Skipped unless `DAGYM_COACH_DRIVE_KEY` is in the test runner's environment
/// (pass it as `TEST_RUNNER_DAGYM_COACH_DRIVE_KEY=…` to xcodebuild); the key reaches the app as
/// a Debug-only launch argument and is never written anywhere but the simulator's Keychain.
/// Not part of the gate: it spends real credit and depends on the network.
final class CoachChatDriveTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["DAGYM_COACH_DRIVE_KEY"] == nil,
            "set DAGYM_COACH_DRIVE_KEY to drive the coach"
        )
    }

    @MainActor
    func testAskForAnAestheticSplit() throws {
        let key = try XCTUnwrap(ProcessInfo.processInfo.environment["DAGYM_COACH_DRIVE_KEY"])
        let question = ProcessInfo.processInfo.environment["DAGYM_COACH_DRIVE_QUESTION"]
            ?? "I want a 4 days a week routine that focuses only on muscles that women like. I want my "
            + "upper body to be aesthetic. I don't care about strength, I just want the bare minimum "
            + "volume to start looking good fast."
        let app = XCUIApplication()
        app.launchArguments = ["-dgUITest", "-dgCoachTrace", "-dgOpenRouterKey", key]
        app.launch()

        let coachTab = app.buttons["tab.coach"].exists
            ? app.buttons["tab.coach"] : app.tabBars.buttons["Coach"]
        XCTAssertTrue(coachTab.waitForExistence(timeout: 45))
        coachTab.tap()
        let entry = app.buttons["coach.chat.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 45), "entry card")
        entry.tap()

        let input = app.textFields["coach.chat.input"].exists
            ? app.textFields["coach.chat.input"] : app.textViews["coach.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "input")
        input.tap()
        input.typeText(question)
        app.buttons["coach.chat.send"].tap()

        // Poll for up to three minutes, snapshotting the transcript every ten seconds.
        let deadline = Date().addingTimeInterval(420)
        var lastSummary = ""
        while Date() < deadline {
            sleep(10)
            // One snapshot per poll: reading live elements races the transcript's updates.
            let tree = try? app.snapshot()
            let chips = labels(in: tree, id: "coach.chat.tool")
            let bubbles = labels(in: tree, id: "coach.chat.assistant")
            let drafts = labels(in: tree, id: "coach.chat.draft")
            let reviews = labels(in: tree, id: "coach.chat.review")
            let strips = labels(in: tree, id: "coach.chat.draft.review")
            let summary = "chips=\(chips.count) bubbles=\(bubbles.count) drafts=\(drafts.count) "
                + "reviews=\(reviews.count) streaming=\(app.buttons["coach.chat.stop"].exists)"
            if summary != lastSummary {
                print("DRIVE \(Int(deadline.timeIntervalSinceNow))s left: \(summary)")
                for chip in chips { print("DRIVE chip: \(chip)") }
                for bubble in bubbles { print("DRIVE assistant: \(bubble.prefix(600))") }
                for draft in drafts { print("DRIVE draft: \(draft.prefix(300))") }
                for review in reviews { print("DRIVE review: \(review.prefix(400))") }
                for strip in strips { print("DRIVE strip: \(strip.prefix(300))") }
                lastSummary = summary
            }
            if !app.buttons["coach.chat.stop"].exists, !bubbles.isEmpty || !drafts.isEmpty {
                // Give a review pass a chance to start before calling the turn done.
                sleep(8)
                if !app.buttons["coach.chat.stop"].exists { break }
            }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        print("DRIVE done: \(lastSummary)")
    }

    @MainActor
    private func labels(in snapshot: XCUIElementSnapshot?, id: String) -> [String] {
        guard let snapshot else { return [] }
        var found: [String] = []
        if snapshot.identifier == id { found.append(snapshot.label) }
        for child in snapshot.children { found += labels(in: child, id: id) }
        return found
    }
}
// swiftlint:enable no_print_statements
