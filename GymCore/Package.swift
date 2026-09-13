// swift-tools-version: 6.2
import PackageDescription

// All training math and logic for DaGym. No UI, no SwiftData, no Apple
// frameworks beyond Foundation, so `swift test` runs without a simulator.
let package = Package(
    name: "GymCore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GymCore", targets: ["GymCore"])
    ],
    targets: [
        .target(name: "GymCore"),
        .testTarget(name: "GymCoreTests", dependencies: ["GymCore"])
    ]
)
