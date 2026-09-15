import Foundation
import XCTest

/// Stable `accessibilityIdentifier` strings, duplicated from
/// `DaGym/Design/AccessibilityIDs.swift`. `DaGymUITests` runs out-of-process
/// against the built app and can't `import DaGym` (it doesn't link against
/// the app module), so the raw values are kept here in lockstep by hand. If
/// you rename an identifier on the app side, rename it here too.
enum A11yID {
    static let homeStart = "home.start"
    static let homeFreestyle = "home.freestyle"

    static let tabToday = "tab.today"
    static let tabRoutines = "tab.routines"
    static let tabProgress = "tab.progress"
    static let tabLibrary = "tab.library"
    static let tabCoach = "tab.coach"

    static let workoutFinish = "workout.finish"

    static func setRowDone(_ index: Int) -> String { "setrow.done.\(index)" }

    static let keypadLog = "keypad.log"

    static func keypadKey(_ digit: String) -> String { "keypad.key.\(digit)" }

    static let summaryDone = "summary.done"

    static let historyList = "history.list"
    static let historyRow0 = "history.row.0"

    static let onboardingNext = "onboarding.next"
    static let onboardingSkip = "onboarding.skip"
    static let onboardingSkipAll = "onboarding.skipAll"
}

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

        let progressTab = tabButton(app, id: A11yID.tabProgress, title: "Progress")
        XCTAssertTrue(
            progressTab.waitForExistence(timeout: defaultTimeout), "tab.progress never appeared"
        )
        progressTab.tap()

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

    /// Library search filters down to a seeded exercise.
    func testLibrarySearchFindsSeededExercise() {
        let app = launchApp()

        let libraryTab = tabButton(app, id: A11yID.tabLibrary, title: "Library")
        XCTAssertTrue(libraryTab.waitForExistence(timeout: defaultTimeout), "tab.library never appeared")
        libraryTab.tap()

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

    /// The Routines tab lists the seeded starter routines.
    func testRoutinesTabShowsStarterRoutines() {
        let app = launchApp()

        let routinesTab = tabButton(app, id: A11yID.tabRoutines, title: "Routines")
        XCTAssertTrue(
            routinesTab.waitForExistence(timeout: defaultTimeout), "tab.routines never appeared"
        )
        routinesTab.tap()

        for name in ["PUSH A", "PULL B", "LEGS"] {
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
