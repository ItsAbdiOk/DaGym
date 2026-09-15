import os

/// The package's one signposter, so Instruments' Points of Interest / os_signpost track shows
/// GymCore's hot paths (an import parse, a streak walk, a voice match, a backup decode) under
/// the same subsystem and category the app uses for launch timing.
enum GymCorePerf {
    static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")
    static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "core")
}
