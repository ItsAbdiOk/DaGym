import XCTest

/// Walks every onboarding step end to end with real choices (not the defaults `SmokeTests`
/// accepts), attaches a screenshot per step, and then checks that Home and Settings reflect
/// those choices: the goal's rest default (Settings › Rest timer), the weekly goal on Home and
/// in Settings › Training, and the active equipment profile (Settings › Equipment profiles).
/// Runs against the fresh in-memory store `-dgUITest` seeds; `-dgOnboarding` forces the flow
/// to start at Welcome regardless of what a previous simulator run left behind.
@MainActor
final class OnboardingWalkthroughTests: XCTestCase {
    private let timeout: TimeInterval = 25

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// A button matched by its visible label, case-insensitively.
    private func button(_ app: XCUIApplication, labelled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private func element(_ app: XCUIApplication, labelled label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private func buttonBeginning(_ app: XCUIApplication, with prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
    }

    /// Settings is one push deep from the You tab, and each of its pages one push deeper: open
    /// the row carrying `rowID` from the index, run `check`, then pop back to the index.
    private func onSettingsPage(_ app: XCUIApplication, rowID: String, check: () -> Void) {
        let row = app.descendants(matching: .any)[rowID]
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "\(rowID) never appeared in Settings")
        row.tap()
        check()
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Asserts the step's title identifier is on screen and attaches a screenshot named after it.
    private func assertStep(_ name: String, in app: XCUIApplication) {
        let title = app.staticTexts[A11yID.onboardingStep(name)]
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "onboarding.step.\(name) never appeared")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "onboarding-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps Continue and waits for the next step's title. A tap synthesised in the first
    /// second or two after launch is occasionally dropped while the seeded store settles, so
    /// one retry is allowed before the step assertion fails for real.
    private func tapNext(_ app: XCUIApplication, expecting nextStep: String? = nil) {
        let next = app.buttons.matching(identifier: A11yID.onboardingNext).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: timeout), "onboarding.next never appeared")
        next.tap()
        guard let nextStep else { return }
        let title = app.staticTexts[A11yID.onboardingStep(nextStep)]
        if !title.waitForExistence(timeout: 5), next.exists {
            next.tap()
        }
    }

    /// The Health permission sheet is a remote view, not a springboard alert, so the interruption
    /// monitor never sees it; it does appear in the app's own hierarchy (pid of the Health
    /// extension). Select every topic, scroll the long list to the bottom and tap Allow. Returns
    /// whether it was shown and answered. If it never shows (e.g. HealthKit unavailable), the
    /// step must have advanced on its own.
    private func allowHealthAccessIfShown(_ app: XCUIApplication) -> Bool {
        let selectAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        guard selectAll.waitForExistence(timeout: 8) else { return false }
        selectAll.tap()
        // The Allow/Don't Allow buttons only materialise once the list is scrolled to its foot
        // (before that the row is a placeholder cell of static texts), so scroll until they do.
        let allow = app.buttons["UIA.Health.Allow.Button"]
        for _ in 0..<8 where !allow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(allow.waitForExistence(timeout: timeout), "Health sheet has no Allow button")
        allow.tap()
        // iOS 27 adds a second page asking how much history to share; its Allow stays disabled
        // until one option is chosen. Earlier systems finish on the first page.
        let allRecorded = app.staticTexts["All Recorded Data and Future Data"]
        if allRecorded.waitForExistence(timeout: 5) {
            allRecorded.tap()
            let finalAllow = app.buttons["Allow"]
            XCTAssertTrue(finalAllow.waitForExistence(timeout: timeout), "History page has no Allow button")
            finalAllow.tap()
        }
        return true
    }

    // MARK: - Test

    // swiftlint:disable:next function_body_length
    func testWalkThroughEveryStepAndLandOnHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-dgUITest", "-dgOnboarding"]

        // Notifications: the system alert is a springboard interruption. Tap Allow when it
        // appears; if it never does (already decided on this simulator), the step must still
        // advance, which the `done` assertion below checks.
        let monitor = addUIInterruptionMonitor(withDescription: "Notifications permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(monitor) }

        app.launch()

        assertStep("welcome", in: app)
        tapNext(app, expecting: "units")

        assertStep("units", in: app)
        let pounds = button(app, labelled: "Pounds")
        XCTAssertTrue(pounds.waitForExistence(timeout: timeout), "Pounds chip never appeared")
        pounds.tap()
        tapNext(app)

        // Strength: rest 3:30 and 4 sessions a week (`Preferences.TrainingGoal`).
        assertStep("goal", in: app)
        let strength = buttonBeginning(app, with: "Strength")
        XCTAssertTrue(strength.waitForExistence(timeout: timeout), "Strength goal row never appeared")
        strength.tap()
        XCTAssertTrue(strength.isSelected, "Strength row did not become selected")
        tapNext(app)

        // Schedule: bump the goal's 4 to 5 and start the week on Sunday.
        assertStep("schedule", in: app)
        let moreSessions = button(app, labelled: "More sessions")
        XCTAssertTrue(moreSessions.waitForExistence(timeout: timeout), "More sessions never appeared")
        moreSessions.tap()
        // The count is a grouped element (`accessibilityElement(children: .ignore)`), so match on
        // label across any element type rather than assuming a static text.
        XCTAssertTrue(
            element(app, labelled: "5 sessions a week").waitForExistence(timeout: 5),
            "Weekly goal did not move from the Strength default of 4 to 5"
        )
        button(app, labelled: "Sunday").tap()
        tapNext(app)

        assertStep("equipment", in: app)
        let homeProfile = button(app, labelled: "Home")
        XCTAssertTrue(homeProfile.waitForExistence(timeout: timeout), "Home equipment chip never appeared")
        homeProfile.tap()
        tapNext(app)

        // Bodyweight is optional; skip it so nothing lands on the bodyweight chart.
        assertStep("bodyweight", in: app)
        app.buttons.matching(identifier: A11yID.onboardingSkip).firstMatch.tap()

        assertStep("health", in: app)
        tapNext(app)
        let healthShown = allowHealthAccessIfShown(app)

        assertStep("notifications", in: app)
        tapNext(app)
        // Interruption monitors only fire on the next interaction; a tap on the (inert)
        // background nudges XCTest to service the alert.
        app.tap()

        assertStep("done", in: app)
        tapNext(app)

        // Home: the schedule shows the 5-session weekly goal.
        let start = app.buttons[A11yID.homeStart]
        XCTAssertTrue(start.waitForExistence(timeout: timeout), "home.start never appeared after onboarding")
        let weeklyGoal = element(app, labelled: "This week, 0 of 5 workouts")
        XCTAssertTrue(weeklyGoal.waitForExistence(timeout: timeout), "Home does not show the 5-session goal")
        let homeShot = XCTAttachment(screenshot: app.screenshot())
        homeShot.name = "home-after-onboarding"
        homeShot.lifetime = .keepAlways
        add(homeShot)

        // Settings: Strength's 3:30 rest default and the Home profile active. Settings lives
        // behind the You tab (iOS 27's tab bar exposes only the title, hence the fallback).
        let youTab = app.buttons[A11yID.tabYou].exists
            ? app.buttons[A11yID.tabYou] : app.tabBars.buttons["You"]
        XCTAssertTrue(youTab.waitForExistence(timeout: timeout), "You tab never appeared")
        youTab.tap()
        let settings = app.descendants(matching: .any).matching(identifier: A11yID.youSettings).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: timeout), "Settings button never appeared")
        settings.tap()

        onSettingsPage(app, rowID: "settings.rest") {
            // SwiftUI prefixes a stepper's label with its value ("3:30, Default rest"), so match the end.
            let rest = app.steppers
                .matching(NSPredicate(format: "label ENDSWITH %@", "Default rest")).firstMatch
            XCTAssertTrue(rest.waitForExistence(timeout: timeout), "Default rest stepper never appeared")
            XCTAssertEqual(rest.value as? String, "3:30", "Strength goal did not set the 3:30 rest default")
        }
        onSettingsPage(app, rowID: "settings.training") {
            let weekly = app.steppers
                .matching(NSPredicate(format: "label ENDSWITH %@", "Weekly goal")).firstMatch
            XCTAssertTrue(weekly.waitForExistence(timeout: timeout), "Weekly goal stepper never appeared")
            XCTAssertEqual(weekly.value as? String, "5 workouts", "Settings does not show the 5-session goal")
        }

        let equipment = app.descendants(matching: .any)["settings.equipment"]
        if !equipment.exists {
            app.swipeUp()
        }
        XCTAssertTrue(equipment.waitForExistence(timeout: timeout), "settings.equipment never appeared")
        equipment.tap()
        let activeHome = button(app, labelled: "Home, active profile")
        XCTAssertTrue(
            activeHome.waitForExistence(timeout: timeout), "Home is not the active equipment profile"
        )
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "settings-after-onboarding\(healthShown ? "-health-allowed" : "")"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
    }
}
