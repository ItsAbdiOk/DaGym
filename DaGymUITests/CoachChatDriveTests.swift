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
        XCTAssertTrue(coachTab.waitForExistence(timeout: 10))
        coachTab.tap()
        let entry = app.buttons["coach.chat.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "entry card")
        entry.tap()

        let input = app.textFields["coach.chat.input"].exists
            ? app.textFields["coach.chat.input"] : app.textViews["coach.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "input")
        input.tap()
        input.typeText(question)
        app.buttons["coach.chat.send"].tap()

        // Poll for up to three minutes, snapshotting the transcript every ten seconds.
        let deadline = Date().addingTimeInterval(180)
        var lastSummary = ""
        while Date() < deadline {
            sleep(10)
            let chips = elements(app, "coach.chat.tool")
            let bubbles = elements(app, "coach.chat.assistant")
            let drafts = elements(app, "coach.chat.draft")
            let summary = "chips=\(chips.count) bubbles=\(bubbles.count) drafts=\(drafts.count) "
                + "streaming=\(app.buttons["coach.chat.stop"].exists)"
            if summary != lastSummary {
                print("DRIVE \(Int(deadline.timeIntervalSinceNow))s left: \(summary)")
                for chip in chips { print("DRIVE chip: \(chip.label)") }
                for bubble in bubbles { print("DRIVE assistant: \(bubble.label.prefix(600))") }
                for draft in drafts { print("DRIVE draft: \(draft.label.prefix(300))") }
                lastSummary = summary
            }
            if !app.buttons["coach.chat.stop"].exists, !bubbles.isEmpty || !drafts.isEmpty { break }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        print("DRIVE done: \(lastSummary)")
    }

    private func elements(_ app: XCUIApplication, _ id: String) -> [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
    }
}
// swiftlint:enable no_print_statements
