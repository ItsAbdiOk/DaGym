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

    static let librarySearch = "library.search"

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

        let progressTab = app.buttons[A11yID.tabProgress]
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

        let libraryTab = app.buttons[A11yID.tabLibrary]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: defaultTimeout), "tab.library never appeared")
        libraryTab.tap()

        let searchField = app.textFields[A11yID.librarySearch]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: defaultTimeout), "library.search never appeared"
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

        let routinesTab = app.buttons[A11yID.tabRoutines]
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
    /// previous simulator run left in `UserDefaults.standard`), mixing Continue and Skip taps,
    /// and confirms it lands on Home with `home.start` visible.
    func testOnboardingCompletes() {
        let app = launchAppForOnboarding()

        let next = app.buttons[A11yID.onboardingNext]
        let skip = app.buttons[A11yID.onboardingSkip]

        // Welcome: "Set Up · 5 Questions" (also tagged onboarding.next) walks the flow instead
        // of skipping it entirely.
        XCTAssertTrue(next.waitForExistence(timeout: defaultTimeout), "onboarding.next never appeared")
        next.tap()

        // Units, Goal, Schedule, Equipment: accept the defaults with Continue.
        for _ in 0..<4 {
            XCTAssertTrue(next.waitForExistence(timeout: defaultTimeout), "onboarding.next never appeared")
            next.tap()
        }

        // Bodyweight, Apple Health, Notifications: skip every optional/permission step.
        for _ in 0..<3 {
            XCTAssertTrue(skip.waitForExistence(timeout: defaultTimeout), "onboarding.skip never appeared")
            skip.tap()
        }

        // Done: "Get Started" (tagged onboarding.next) finishes onboarding.
        XCTAssertTrue(next.waitForExistence(timeout: defaultTimeout), "onboarding.next never appeared")
        next.tap()

        let startButton = app.buttons[A11yID.homeStart]
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
