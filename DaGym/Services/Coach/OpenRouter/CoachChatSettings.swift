import Foundation

/// Where the lifter's OpenRouter key lives: the Keychain, under one account name, and nowhere
/// else — not `Preferences`, not a backup, not a log line.
enum CoachChatSettings {
    /// `KeychainStore` account name for the OpenRouter API key.
    static let keychainAccount = "openrouter.apiKey"

    static func apiKey() -> String? {
        guard let key = KeychainStore.string(account: keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else { return nil }
        return key
    }

    /// The screenshot build has no key and never sends; the flag stands in for one so the chat
    /// opens on its canned thread instead of the "add your key" state.
    static var hasAPIKey: Bool { LaunchFlags.isScreenshotting || apiKey() != nil }

    /// Saves a pasted key; an empty paste removes it instead of storing a blank.
    /// Debug builds only: `-dgOpenRouterKey <key>` seeds the Keychain and grants consent so a
    /// simulator run can be driven from the command line. The value lives in the simulator's
    /// process arguments and its Keychain, nowhere else; a Release build ignores the flag.
    @MainActor
    static func adoptLaunchArgumentKey(preferences: Preferences) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-dgOpenRouterKey"), index + 1 < arguments.count else {
            return
        }
        saveAPIKey(arguments[index + 1])
        preferences.coachChatConsentGiven = true
        #endif
    }

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeAPIKey()
        } else {
            KeychainStore.set(trimmed, account: keychainAccount)
        }
    }

    static func removeAPIKey() {
        KeychainStore.remove(account: keychainAccount)
    }

    /// The `apiKey:` closure `OpenRouterClient` wants — reads the Keychain per request, so a
    /// key saved in Settings is picked up without rebuilding the client.
    static let keyProvider: @Sendable () -> String? = { apiKey() }
}

/// The chat preferences the engine reads (`coachModelID`, `coachReviewerModelID`,
/// `coachChatConsentGiven`), carried as a value so the Services layer never touches
/// `Preferences` directly. The Store slice builds one from `Preferences`; tests build one inline.
struct CoachChatConfiguration: Equatable, Sendable {
    /// The drafter: runs the conversation and makes the proposals.
    static let defaultModelID = "google/gemini-3.1-pro-preview"
    /// The second opinion: gets every proposal and agrees or puts up its own version.
    static let defaultReviewerModelID = "anthropic/claude-opus-5"

    var modelID: String = defaultModelID
    /// nil: no second opinion, proposals go straight to the lifter.
    var reviewerModelID: String? = defaultReviewerModelID
    var consentGiven = false
    /// Generation cap per reply; tool rounds each get their own. Reasoning tokens count against
    /// it on Gemini and Claude alike, and a high-effort think about a four-day programme can run
    /// past 2k on its own — which came back as an empty reply. 16k leaves room for both.
    var maxTokens = 16_384

    /// The chat can send: consent was given and a key is in the Keychain.
    var isReady: Bool { consentGiven && CoachChatSettings.hasAPIKey }

    /// "Gemini 3.1 Pro" — what the cards and the transcript call the drafter.
    var drafterDisplayName: String { Self.displayName(forModelID: modelID) }
    /// "Claude Opus 5"; nil when the second opinion is off.
    var reviewerDisplayName: String? { reviewerModelID.map(Self.displayName(forModelID:)) }
    /// "Gemini" — the one word a chip has room for.
    var drafterShortName: String { Self.shortName(forModelID: modelID) }
    /// "Opus"; nil when the second opinion is off.
    var reviewerShortName: String? { reviewerModelID.map(Self.shortName(forModelID:)) }

    /// `google/gemini-3.1-pro-preview` → "Gemini 3.1 Pro", `anthropic/claude-opus-5` →
    /// "Claude Opus 5", `openai/gpt-5` → "GPT 5". Vendor dropped, release-channel suffixes
    /// dropped, words capitalised, acronyms upper-cased.
    static func displayName(forModelID id: String) -> String {
        let words = nameWords(forModelID: id)
        guard !words.isEmpty else { return id }
        return words.map { word in
            acronyms.contains(word) ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// The family word: "Opus" for `claude-opus-5`, "Gemini" for `gemini-3.1-pro-preview`,
    /// "GPT" for `gpt-5`.
    static func shortName(forModelID id: String) -> String {
        let words = nameWords(forModelID: id)
        guard let first = words.first else { return id }
        let family = first == "claude"
            ? words.dropFirst().first(where: { Double($0) == nil }) ?? first
            : first
        return acronyms.contains(family)
            ? family.uppercased()
            : family.prefix(1).uppercased() + family.dropFirst()
    }

    private static let acronyms: Set<String> = ["gpt", "glm", "llm", "moe", "r1", "o1", "o3", "o4"]
    private static let droppedSuffixes: Set<String> = ["preview", "latest", "beta", "exp", "experimental"]

    private static func nameWords(forModelID id: String) -> [String] {
        let slug = id.split(separator: "/").last.map(String.init) ?? id
        let base = slug.split(separator: ":").first.map(String.init) ?? slug
        var words = base.split(separator: "-").map { $0.lowercased() }
        while let last = words.last, droppedSuffixes.contains(last) || (last.count == 8 && Int(last) != nil) {
            words.removeLast()
        }
        return words
    }
}
