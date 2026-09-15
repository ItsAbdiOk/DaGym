import Darwin
import Foundation
import os

/// Debug-only cold-launch stopwatch. With `-dgLaunchTiming` the first `RootView` appearance
/// writes `Documents/launch-timing.json` with the milliseconds from process creation
/// (`kinfo_proc.p_starttime`, so dyld and static initialisers are included) to first frame.
/// `scripts/perf-baseline.sh` reads that file after each launch; nothing else reads it, and a
/// Release build compiles the whole thing to a no-op.
enum LaunchTiming {
    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")
    private static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")
    nonisolated(unsafe) private static var recorded = false

    /// Milliseconds since the process was created, or nil if the sysctl is unavailable.
    static func millisecondsSinceProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return (Date().timeIntervalSince1970 - started) * 1_000
    }

    /// Call from the root view's first `onAppear`. Idempotent; a no-op without the flag.
    static func markFirstFrame() {
        #if DEBUG
        guard !recorded, ProcessInfo.processInfo.arguments.contains("-dgLaunchTiming") else { return }
        recorded = true
        guard let millis = millisecondsSinceProcessStart() else { return }
        signposter.emitEvent("firstFrame", "\(millis, format: .fixed(precision: 0)) ms")
        logger.notice("cold launch to first frame: \(millis, format: .fixed(precision: 0)) ms")
        let payload: [String: Any] = ["firstFrameMillis": millis, "recordedAt": Date().timeIntervalSince1970]
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: documents.appendingPathComponent("launch-timing.json"), options: .atomic)
        #endif
    }
}
