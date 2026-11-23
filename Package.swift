// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTunes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftTunes", targets: ["SwiftTunes"]),
        .executable(name: "tunes-lifeline", targets: ["tunes-lifeline"]),
    ],
    targets: [
        .target(name: "TunesContract"),
        .target(name: "TunesRules"),
        .target(name: "TunesEngine", dependencies: ["TunesContract", "TunesRules"]),
        .target(name: "TunesPanel", dependencies: ["TunesContract"]),
        .executableTarget(name: "SwiftTunes", dependencies: ["TunesContract", "TunesPanel", "TunesEngine"]),
        .executableTarget(name: "tunes-lifeline"),

        .target(name: "TunesFakes", path: "Tests/TunesFakes"),
        .testTarget(name: "TunesRulesTests", dependencies: ["TunesRules"]),
        .testTarget(name: "TunesEngineTests", dependencies: ["TunesEngine", "TunesContract", "TunesFakes"]),
        .testTarget(
            name: "TunesPanelTests",
            dependencies: ["TunesPanel", "TunesContract"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
