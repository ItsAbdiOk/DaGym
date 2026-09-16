import Foundation

/// Stable `accessibilityIdentifier` strings shared by the app and
/// `DaGymUITests`. The UI-test bundle can't `import DaGym` (it doesn't link
/// against the app module), so `DaGymUITests` keeps its own copy of this
/// enum with identical raw values — see the comment there if the two ever
/// drift apart.
enum A11yID {
    static let homeStart = "home.start"
    static let homeFreestyle = "home.freestyle"
    static let homeWeekReview = "home.weekReview"

    static let tabToday = "tab.today"
    static let tabRoutines = "tab.routines"
    static let tabProgress = "tab.progress"
    static let tabLibrary = "tab.library"
    static let tabCoach = "tab.coach"

    static let workoutFinish = "workout.finish"
    static let settingsWorkoutLayout = "settings.workout.layout"

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

    static let coachChatEntry = "coach.chat.entry"
    static let coachChatClose = "coach.chat.close"
    static let coachChatThreadMenu = "coach.chat.threads"
    static let coachChatTranscript = "coach.chat.transcript"
    static let coachChatInput = "coach.chat.input"
    static let coachChatSend = "coach.chat.send"
    static let coachChatStop = "coach.chat.stop"
    static let coachChatSuggestedPrompt = "coach.chat.prompt"
    static let coachChatUserBubble = "coach.chat.user"
    static let coachChatAssistantBubble = "coach.chat.assistant"
    static let coachChatToolChip = "coach.chat.tool"
    static let coachChatDraftCard = "coach.chat.draft"
    static let coachChatDraftApply = "coach.chat.draft.apply"
    static let coachChatDraftDiscard = "coach.chat.draft.discard"
    static let coachChatDraftOrigin = "coach.chat.draft.origin"
    static let coachChatDraftReview = "coach.chat.draft.review"
    static let coachChatDraftRationale = "coach.chat.draft.rationale"
    static let coachChatReviewRow = "coach.chat.review"
    static let coachChatShowMore = "coach.chat.showMore"
    static let coachChatDraftReason = "coach.chat.draft.reason"
    static let coachChatErrorBanner = "coach.chat.error"
    static let coachChatErrorAction = "coach.chat.error.action"
    static let coachKeyRow = "coach.settings.key"
    static let coachKeyField = "coach.settings.keyField"
    static let coachKeySave = "coach.settings.keySave"
    static let coachModelRow = "coach.settings.model"
    static let coachModelSearch = "coach.settings.modelSearch"
    static let coachReviewerRow = "coach.settings.reviewer"
    static let coachModelOff = "coach.settings.modelOff"
    static let coachCostHint = "coach.settings.costHint"
    static let coachConsentAgree = "coach.settings.consentAgree"
    static let coachConsentCancel = "coach.settings.consentCancel"
    static let coachWhatIsSent = "coach.settings.whatIsSent"
    static let coachUsageRow = "coach.settings.usage"
    static let coachUsageTotal = "coach.usage.total"
    static let coachUsageReset = "coach.usage.reset"
    static let coachMemoryRow = "coach.settings.memory"
    static let coachMemoryList = "coach.memory.list"
    static let coachMemoryForgetAll = "coach.memory.forgetAll"

    static let walletAdd = "gymcard.wallet.add"
    static let walletOpen = "gymcard.wallet.open"
    static let walletNote = "gymcard.wallet.note"

    static let historyList = "history.list"
    static let historyRow0 = "history.row.0"
    static let historyNote = "history.note"
    static let routinesStarterPlan = "routines.starterPlan"
    /// `name` is the `StarterProgramKind` raw value ("Push/Pull/Legs").
    static func starterPlan(_ name: String) -> String { "starterPlan.\(name)" }

    static let onboardingNext = "onboarding.next"
    static let onboardingSkip = "onboarding.skip"
    /// The Welcome step's "Skip and start lifting" — distinct from `onboardingSkip` (which
    /// skips one optional step) because this one skips the whole flow straight to `RootView`.
    static let onboardingSkipAll = "onboarding.skipAll"
    /// Each onboarding step's title, so a UI test can assert which step is showing.
    /// `name` is the `OnboardingStep` case name: "welcome", "units", ... "done".
    static func onboardingStep(_ name: String) -> String { "onboarding.step.\(name)" }
}
