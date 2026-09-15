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

    static var hasAPIKey: Bool { apiKey() != nil }

    /// Saves a pasted key; an empty paste removes it instead of storing a blank.
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

/// The two `Preferences` the chat reads (`coachModelID`, `coachChatConsentGiven`), carried as
/// a value so the Services layer never touches `Preferences` directly. The Store slice builds
/// one from `Preferences`; tests build one inline.
struct CoachChatConfiguration: Equatable, Sendable {
    /// Confirmed against GET /api/v1/models: `anthropic/claude-sonnet-5` (Claude Sonnet 5).
    static let defaultModelID = "anthropic/claude-sonnet-5"

    var modelID: String = defaultModelID
    var consentGiven = false
    /// Generation cap per reply; tool rounds each get their own.
    var maxTokens = 2_048

    /// The chat can send: consent was given and a key is in the Keychain.
    var isReady: Bool { consentGiven && CoachChatSettings.hasAPIKey }
}
