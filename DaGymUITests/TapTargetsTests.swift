import Foundation
import XCTest

/// "Anything that shows a number, a name or a summary is a door to the screen that owns it."
/// Taps the most important doors on Today, You, Progress and History and asserts the
/// destination's title appears. Runs on the `-dgScreenshots` store (eight weeks of history,
/// a scheduled routine, a bodyweight series) so every tile has a number on it.
@MainActor
final class TapTargetsTests: XCTestCase {
    private let timeout: TimeInterval = 25

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dgScreenshots"]
        app.launch()
        return app
    }

    private func tabButton(_ app: XCUIApplication, id: String, title: String) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.waitForExistence(timeout: 3) { return byID }
        return app.tabBars.buttons[title]
    }

    /// Taps `id` and waits for a navigation bar titled `title`; `back` pops it again.
    private func assertDoor(
        _ app: XCUIApplication, id: String, opens title: String, back: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let door = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: timeout), "\(id) never appeared", file: file, line: line)
        door.tap()
        let bar = app.navigationBars[title]
        XCTAssertTrue(
            bar.waitForExistence(timeout: timeout), "\(id) did not open \(title)", file: file, line: line
        )
        if back { popBack(app) }
    }

    private func popBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: timeout), "no back button")
        back.tap()
    }

    /// Today: the date kicker, the week and bodyweight tiles, the recovery row and the hero's
    /// muscles line each open the screen that owns them; the routine title opens the builder.
    func testTodayDoors() {
        let app = launchApp()
        assertDoor(app, id: A11yID.homeDate, opens: "History")
        assertDoor(app, id: A11yID.homeWeekTile, opens: "This week")
        assertDoor(app, id: A11yID.homeBodyweightTile, opens: "Body")
        assertDoor(app, id: A11yID.homeRecovery, opens: "Muscle map")
        assertDoor(app, id: A11yID.homeHits, opens: "Muscle map")

        let title = app.descendants(matching: .any)[A11yID.homeHeroTitle].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "home.heroTitle never appeared")
        title.tap()
        let builder = app.staticTexts["Edit routine"]
        XCTAssertTrue(builder.waitForExistence(timeout: timeout), "builder never opened")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Cancel did not return to Today")
    }

    /// You: the ring opens Progress; Volume and Streak open This week; Bodyweight opens Body.
    func testYouDoors() {
        let app = launchApp()
        let youTab = tabButton(app, id: A11yID.tabYou, title: "You")
        XCTAssertTrue(youTab.waitForExistence(timeout: timeout), "tab.you never appeared")
        youTab.tap()
        assertDoor(app, id: A11yID.youRing, opens: "Progress")
        assertDoor(app, id: A11yID.youVolume, opens: "This week")
        assertDoor(app, id: A11yID.youBodyweight, opens: "Body")

        // Streak lands on the Consistency segment, not just the screen.
        assertDoor(app, id: A11yID.youStreak, opens: "This week", back: false)
        let consistency = app.descendants(matching: .any)[A11yID.thisWeekSegment("Consistency")].firstMatch
        XCTAssertTrue(consistency.waitForExistence(timeout: timeout), "Consistency segment missing")
        XCTAssertTrue(consistency.isSelected, "Streak did not land on Consistency")
    }

    /// Progress hub: the rings open This week, the Top muscle tile the muscle map; History's
    /// "kg lifted" tile opens Records.
    func testProgressAndHistoryDoors() {
        let app = launchApp()
        let youTab = tabButton(app, id: A11yID.tabYou, title: "You")
        XCTAssertTrue(youTab.waitForExistence(timeout: timeout), "tab.you never appeared")
        youTab.tap()

        assertDoor(app, id: A11yID.youHistory, opens: "History", back: false)
        assertDoor(app, id: A11yID.historyTile("lifted"), opens: "This week", back: false)
        let records = app.descendants(matching: .any)[A11yID.thisWeekSegment("Records")].firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: timeout), "Records segment missing")
        XCTAssertTrue(records.isSelected, "kg lifted did not land on Records")
        popBack(app)
        popBack(app)

        assertDoor(app, id: A11yID.youProgress, opens: "Progress", back: false)
        assertDoor(app, id: A11yID.progressRings, opens: "This week")
        // The muscle tile lands on that muscle's detail sheet over the map, so it goes last:
        // the sheet covers the back button.
        assertDoor(app, id: A11yID.progressTopMuscle, opens: "Muscle map", back: false)
        // `dgLabel()` uppercases the kicker on screen, so match without case.
        let detail = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] %@", "What fatigued it")
        ).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: timeout), "no muscle detail sheet")
    }
}
