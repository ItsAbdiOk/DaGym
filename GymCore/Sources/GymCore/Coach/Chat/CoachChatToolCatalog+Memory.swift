import Foundation

/// The two memory tools, offered to the drafter and the reviewer alike. `remember` files a
/// durable fact the lifter stated; `recall` reads the facts back, filtered. The current facts
/// are also printed in the system prompt (`CoachChatPrompt.memoryBlock`), so `recall` is for
/// the long tail — an old injury, a fact past the prompt's line cap.
extension CoachChatToolCatalog {
    public static let maxExpiryDays = 365

    static let memoryTools: [CoachChatTool] = [
        CoachChatTool(
            name: .remember,
            description: "Keep one durable fact about the lifter for future chats: an injury or pain, "
                + "an exercise they hate or love, a schedule or equipment change, a goal. Call it once "
                + "per fact, when the lifter states it. Never store weights, sets, reps or dates of "
                + "sessions — the log has those. A restated fact replaces the old one.",
            parameters: .object(
                properties: [
                    "text": .string(
                        "The fact in one short sentence, at most \(CoachMemoryValidation.maxTextLength) "
                            + "characters, e.g. 'Knees hurt on leg press; prefers hack squat'."
                    ),
                    "topic": .string(
                        "What kind of fact it is.", enum: CoachMemoryFact.Topic.allCases.map(\.rawValue)
                    ),
                    "expires_in_days": .integer(
                        "Forget it after this many days — for temporary facts like a six-week "
                            + "restriction. Omit for facts that stand until the lifter says otherwise.",
                        in: 1...maxExpiryDays
                    )
                ],
                required: ["text", "topic"]
            )
        ),
        CoachChatTool(
            name: .recall,
            description: "Facts remembered from earlier chats, newest first, optionally filtered by "
                + "topic and/or words from the text. The most recent facts are already in your "
                + "instructions; call this for older ones or to check before proposing around an "
                + "injury or piece of equipment.",
            parameters: .object(
                properties: [
                    "topic": .string(
                        "Only facts of this kind.", enum: CoachMemoryFact.Topic.allCases.map(\.rawValue)
                    ),
                    "query": .string("Words to look for in the fact text, e.g. 'knee' or 'leg press'.")
                ]
            )
        )
    ]
}
