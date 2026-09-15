import Foundation

/// Stable `accessibilityIdentifier` strings shared by the app and
/// `DaGymUITests`. The UI-test bundle can't `import DaGym` (it doesn't link
/// against the app module), so `DaGymUITests` keeps its own copy of this
/// enum with identical raw values — see the comment there if the two ever
/// drift apart.
enum A11yID {
    static let homeStart = "home.start"
    static let homeFreestyle = "home.freestyle"

    static let tabToday = "tab.today"
    static let tabRoutines = "tab.routines"
    static let tabProgress = "tab.progress"
    static let tabLibrary = "tab.library"
    static let tabCoach = "tab.coach"

    static let workoutFinish = "workout.finish"

    /// `index` is the set's position within its exercise (0-based).
    static func setRowDone(_ index: Int) -> String { "setrow.done.\(index)" }

    static let keypadLog = "keypad.log"

    /// `digit` is a single character, e.g. "0"..."9".
    static func keypadKey(_ digit: String) -> String { "keypad.key.\(digit)" }

    static let summaryDone = "summary.done"
    static let debriefCard = "summary.debrief"
    static let coachReview = "coach.review"
    static let coachQuestion = "coach.question"
    static let coachAnswer = "coach.answer"
    static let coachApplyFailure = "coach.applyFailure"
    static let programBuild = "program.build"
    static let programApply = "program.apply"
    static let coachStatus = "coach.status"

    static let historyList = "history.list"
    static let historyRow0 = "history.row.0"

    static let onboardingNext = "onboarding.next"
    static let onboardingSkip = "onboarding.skip"
    /// The Welcome step's "Skip and start lifting" — distinct from `onboardingSkip` (which
    /// skips one optional step) because this one skips the whole flow straight to `RootView`.
    static let onboardingSkipAll = "onboarding.skipAll"
    /// Each onboarding step's title, so a UI test can assert which step is showing.
    /// `name` is the `OnboardingStep` case name: "welcome", "units", ... "done".
    static func onboardingStep(_ name: String) -> String { "onboarding.step.\(name)" }
}
