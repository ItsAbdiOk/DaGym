import Foundation

/// Launch-argument deep link used only for screenshots and review builds:
/// `-dgScreen home|workout|rest|library|exerciseDetail|builder|summary|history|backfill`.
/// Ignored in Release.
enum DebugRoute: String, CaseIterable {
    case home, workout, rest, library, exerciseDetail, builder, summary, history, backfill
    case keypad, effort, swap, newExercise

    static var fromLaunchArguments: DebugRoute? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-dgScreen"), idx + 1 < args.count else { return nil }
        return DebugRoute(rawValue: args[idx + 1])
        #else
        return nil
        #endif
    }
}
