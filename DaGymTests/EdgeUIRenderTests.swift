import Foundation
import GymCore
import SwiftUI
import Testing

@testable import DaGym

/// The pure pieces behind the appearance / Dynamic Type edge-case pass: colours and layout
/// rules that a screenshot showed wrong in dark mode or at the largest accessibility size.
@MainActor
@Suite("Edge-case UI render rules")
struct EdgeUIRenderTests {
    private func day(isToday: Bool) -> MonthCalendarDay {
        MonthCalendarDay(
            key: "2026-09-17", date: Date(), dayNumber: 17, state: .free, isToday: isToday, isPast: false
        )
    }

    @Test("today's calendar cell is the page inversion, so it flips with the scheme")
    func todayCellInverts() {
        let today = MonthCalendarDayCell(day: day(isToday: true), maxLoadKg: 0, isSelected: false)
        // Ink fill, page-coloured number: both are dynamic tokens, unlike the fixed near-black
        // hex that vanished against the card in dark mode.
        #expect(today.fill == DGColor.ink1)
        #expect(today.ink == DGColor.bgBase)
        let free = MonthCalendarDayCell(day: day(isToday: false), maxLoadKg: 0, isSelected: false)
        #expect(free.fill != DGColor.ink1)
        #expect(free.ink == DGColor.ink1)
    }

    @Test("the You hub's panels drop to a low white in dark mode")
    func youPanelDarkFill() {
        #expect(YouPanel.fillOpacity(dark: false) == 0.7)
        #expect(YouPanel.fillOpacity(dark: true) < 0.15)
        #expect(YouPanel.edgeOpacity(dark: true) < YouPanel.edgeOpacity(dark: false))
    }

    @Test("kickers stop scaling at the first accessibility size")
    func kickerCap() {
        // A kicker over a number must not outgrow it: `.caption` alone reaches 43 pt at the
        // largest setting; capped here it stays around 2× its base.
        #expect(DGFont.kickerCap == .accessibility1)
        #expect(DGFont.kickerCap < .accessibility2)
    }

    @Test("library names get a second line only at accessibility sizes")
    func libraryNameLineLimit() {
        #expect(LibraryRow.nameLineLimit(.large) == 1)
        #expect(LibraryRow.nameLineLimit(.xxxLarge) == 1)
        #expect(LibraryRow.nameLineLimit(.accessibility1) == 2)
        #expect(LibraryRow.nameLineLimit(.accessibility5) == 2)
    }

    @Test("the edge-state screenshot screens resolve from their launch-argument names")
    func screenshotScreensResolve() {
        let names = [
            "you", "history", "workoutDetail", "homeRest", "homeNoRoutines", "homeSample",
            "homeDeload", "muscleBalance", "muscleStrength", "onboarding"
        ]
        for name in names {
            #expect(ScreenshotScreen(rawValue: name) != nil, "\(name) missing")
        }
        // Only the two workout screens open with the mid-set session; a Today variant must not,
        // or the shell opens under a "Resume Workout?" dialog.
        #expect(!ScreenshotScreen.homeDeload.needsInProgressWorkout)
        #expect(!ScreenshotScreen.you.needsInProgressWorkout)
    }
}
