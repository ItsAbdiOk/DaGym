import Foundation
import GymCore

/// The engine's pure helpers: transcript wording, the debug trace and the chip subject.
extension CoachChatEngine {
    static func failureLine(for error: OpenRouterError) -> String {
        switch error.kind {
        case .missingKey: "No OpenRouter key is set — add one in Settings › Coach."
        case .unauthorized: "OpenRouter rejected the key. Check it in Settings › Coach."
        case .insufficientCredits: "The OpenRouter account is out of credit."
        case .rateLimited: "OpenRouter is rate-limiting this key. Try again in a moment."
        case .badRequest: "The model rejected that request. \(error.detail)"
        case .server: "OpenRouter had a server error. Try again."
        case .network: "Couldn't reach OpenRouter. Check the connection and try again."
        case .decoding: "OpenRouter sent something this build couldn't read."
        }
    }

    /// `-dgCoachTrace` (Debug only) logs each round's shape — counts, tool names, argument
    /// sizes, never message text or the key — so a silent turn can be read off `log stream`.
    static func trace(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-dgCoachTrace") else { return }
        let text = line()
        logger.notice("trace: \(text, privacy: .public)")
        #endif
    }

    /// The one argument worth showing on a step chip — "Reading exercise history · Bench Press",
    /// "Searching exercises · delts" — so the trace says what the coach is looking at.
    static func chipSubject(from argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["exercise_name", "name", "muscle", "query", "routine_name", "goal"] {
            if let value = object[key] as? String, !value.isEmpty { return String(value.prefix(40)) }
        }
        if let weeks = object["weeks"] as? Int { return "\(weeks) weeks" }
        if let target = object["target_kg"] as? Double { return "\(Int(target)) kg" }
        return nil
    }

    static func errorJSON(_ message: String) -> String {
        guard let data = try? JSONEncoder().encode(["error": message]),
              let json = String(data: data, encoding: .utf8)
        else { return #"{"error":"Tool failed."}"# }
        return json
    }

    /// The streamed fragments in index order, nameless ones dropped. A tool with no parameters
    /// streams no argument fragments at all; replaying the call with `"arguments": ""` is
    /// rejected as invalid JSON on the next round, which silently killed every turn that began
    /// with `get_profile`, so an empty argument string becomes `{}`.
    static func orderedCalls(_ calls: [Int: OpenRouterWire.ToolCall]) -> [OpenRouterWire.ToolCall] {
        calls.keys.sorted().compactMap { calls[$0] }
            .map { call in
                var call = call
                // Some providers stream the name with punctuation glued on ("get_profile=").
                call.function.name = String(
                    call.function.name.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                )
                if call.function.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    call.function.arguments = "{}"
                }
                return call
            }
            .filter { !$0.function.name.isEmpty }
    }
}
