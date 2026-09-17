import Foundation
import XCTest

/// End-to-end smoke coverage for the app's core loop, run against a fresh
/// in-memory, seeded store (`-dgUITest`, see `LaunchFlags`) so these never
/// depend on — or pollute — whatever is on a developer's simulator.
@MainActor
final class SmokeTests: XCTestCase {
    private let defaultTimeout: TimeInterval = 25

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A root tab's bar button. iOS 26 exposed the `accessibilityIdentifier` set on the tab's
    /// label; iOS 27's tab bar drops it and exposes only the title, so fall back to that.
    private func tabButton(_ app: XCUIApplication, id: String, title: String) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.waitForExistence(timeout: 3) { return byID }
        return app.tabBars.buttons[title]
    }

    /// Progress, Library and Coach are one push deep from the You tab now: open the tab, then
    /// tap the hub tile/row carrying `destinationID`.
    private func openFromYou(_ app: XCUIApplication, destinationID: String, title: String) {
        let youTab = tabButton(app, id: A11yID.tabYou, title: "You")
        XCTAssertTrue(youTab.waitForExistence(timeout: defaultTimeout), "tab.you never appeared")
        youTab.tap()
        let destination = app.descendants(matching: .any)[destinationID]
        XCTAssertTrue(
            destination.waitForExistence(timeout: defaultTimeout), "\(destinationID) never appeared on You"
        )
        destination.tap()
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dgUITest"]
        app.launch()
        return app
    }

    private func launchAppForOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dgUITest", "-dgOnboarding"]
        app.launch()
        return app
    }

    /// Start a workout from Home, log a set, finish, and confirm it lands in History.
    func testLogAWorkoutEndToEnd() {
        let app = launchApp()

        let startButton = app.buttons[A11yID.homeStart]
        XCTAssertTrue(startButton.waitForExistence(timeout: defaultTimeout), "home.start never appeared")
        startButton.tap()

        let finishButton = app.buttons[A11yID.workoutFinish]
        XCTAssertTrue(
            finishButton.waitForExistence(timeout: defaultTimeout), "workout.finish never appeared"
        )

        let firstSetDone = app.buttons[A11yID.setRowDone(0)]
        XCTAssertTrue(
            firstSetDone.waitForExistence(timeout: defaultTimeout), "setrow.done.0 never appeared"
        )
        firstSetDone.tap()

        finishButton.tap()

        let confirmFinish = app.buttons["Finish workout"]
        XCTAssertTrue(
            confirmFinish.waitForExistence(timeout: defaultTimeout),
            "Finish workout confirmation button never appeared"
        )
        confirmFinish.tap()

        let summaryDone = app.buttons[A11yID.summaryDone]
        XCTAssertTrue(
            summaryDone.waitForExistence(timeout: defaultTimeout), "summary.done never appeared"
        )
        summaryDone.tap()

        openFromYou(app, destinationID: A11yID.youHistory, title: "History")

        // SwiftUI's `List` can be backed by either a table or a collection
        // view depending on OS version and style, so match by identifier
        // against any element type rather than assuming one.
        let historyList = app.descendants(matching: .any)[A11yID.historyList]
        XCTAssertTrue(
            historyList.waitForExistence(timeout: defaultTimeout), "history.list never appeared"
        )
        XCTAssertTrue(
            historyList.cells.firstMatch.waitForExistence(timeout: defaultTimeout),
            "history.list has no cells after finishing a workout"
        )
    }

    /// The workout's chevron minimises it: the cover goes, the resume strip sits above the tab
    /// bar on every tab, and a tap on it brings the same session (and its Finish button) back.
    func testMinimiseAndResumeWorkout() {
        let app = launchApp()

        let startButton = app.buttons[A11yID.homeStart]
        XCTAssertTrue(startButton.waitForExistence(timeout: defaultTimeout), "home.start never appeared")
        startButton.tap()

        let minimise = app.buttons[A11yID.workoutMinimise]
        XCTAssertTrue(minimise.waitForExistence(timeout: defaultTimeout), "workout.minimise never appeared")
        minimise.tap()

        let resumeBar = app.buttons[A11yID.workoutResumeBar]
        XCTAssertTrue(resumeBar.waitForExistence(timeout: defaultTimeout), "workout.resumeBar never appeared")
        XCTAssertFalse(app.buttons[A11yID.workoutFinish].exists, "the cover should be down while minimised")

        // The strip follows the lifter across tabs.
        let trainTab = tabButton(app, id: A11yID.tabTrain, title: "Train")
        XCTAssertTrue(trainTab.waitForExistence(timeout: defaultTimeout), "tab.train never appeared")
        trainTab.tap()
        XCTAssertTrue(resumeBar.waitForExistence(timeout: defaultTimeout), "resume bar missing on Train")

        resumeBar.tap()
        let finishButton = app.buttons[A11yID.workoutFinish]
        XCTAssertTrue(finishButton.waitForExistence(timeout: defaultTimeout), "the workout did not come back")
        XCTAssertFalse(resumeBar.exists, "the resume bar should go once the cover is back")
    }

    /// Library search filters down to a seeded exercise.
    func testLibrarySearchFindsSeededExercise() {
        let app = launchApp()

        openFromYou(app, destinationID: A11yID.youLibrary, title: "Exercise library")

        // The library uses the system `.searchable` field, which XCUITest exposes as a
        // search field rather than a text field and which carries no custom identifier.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(
            searchField.waitForExistence(timeout: defaultTimeout), "library search never appeared"
        )
        searchField.tap()
        searchField.typeText("bench")

        let benchCell = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Bench")
        ).firstMatch
        XCTAssertTrue(benchCell.waitForExistence(timeout: 5), "No cell containing \"Bench\" appeared")
    }

    /// The Train tab lists the Push/Pull/Legs trio the UI-test store seeds (a real install ships none).
    func testRoutinesTabShowsStarterRoutines() {
        let app = launchApp()

        let trainTab = tabButton(app, id: A11yID.tabTrain, title: "Train")
        XCTAssertTrue(
            trainTab.waitForExistence(timeout: defaultTimeout), "tab.train never appeared"
        )
        trainTab.tap()

        for name in ["Push A", "Pull B", "Legs"] {
            let text = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", name)
            ).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: defaultTimeout), "\"\(name)\" never appeared")
        }
    }

    /// Walks the whole onboarding flow (`-dgOnboarding` forces it to show, resetting whatever a
    /// previous simulator run left in `UserDefaults.standard`), skipping every optional step and
    /// accepting the defaults on the rest, and confirms it lands on Home with `home.start`
    /// visible. Steps are discovered rather than counted, and `onboarding.next` is resolved
    /// with `firstMatch`, so adding a step or a second Continue-tagged control to one changes
    /// nothing here — only a step with no way forward, or one that never reaches Home, fails.
    func testOnboardingCompletes() {
        let app = launchAppForOnboarding()

        let next = app.buttons.matching(identifier: A11yID.onboardingNext).firstMatch
        let skip = app.buttons.matching(identifier: A11yID.onboardingSkip).firstMatch
        let startButton = app.buttons[A11yID.homeStart]

        // Welcome: "Set Up · 5 Questions" (also tagged onboarding.next) walks the flow instead
        // of skipping it entirely.
        XCTAssertTrue(next.waitForExistence(timeout: defaultTimeout), "onboarding.next never appeared")
        next.tap()

        // Every following step shows Continue, and the optional / permission steps also show
        // Skip; take Skip when it's offered. Bounded well above the real step count so a step
        // that never advances fails fast instead of looping.
        for _ in 0..<12 {
            if startButton.waitForExistence(timeout: 1) { break }
            XCTAssertTrue(next.waitForExistence(timeout: defaultTimeout), "onboarding.next never appeared")
            if skip.exists {
                skip.tap()
            } else {
                next.tap()
            }
        }

        XCTAssertTrue(startButton.waitForExistence(timeout: defaultTimeout), "home.start never appeared")
    }

    /// Welcome's "Skip and start lifting" (`onboarding.skipAll`) finishes onboarding immediately
    /// with defaults, bypassing every question — a separate, shorter path onto Home from the
    /// same `OnboardingFlow` → `RootView` hand-off `testOnboardingCompletes` exercises.
    func testOnboardingSkipAllLandsOnHome() {
        let app = launchAppForOnboarding()

        let skipAll = app.buttons[A11yID.onboardingSkipAll]
        XCTAssertTrue(skipAll.waitForExistence(timeout: defaultTimeout), "onboarding.skipAll never appeared")
        skipAll.tap()

        let startButton = app.buttons[A11yID.homeStart]
        XCTAssertTrue(startButton.waitForExistence(timeout: defaultTimeout), "home.start never appeared")
    }
}
