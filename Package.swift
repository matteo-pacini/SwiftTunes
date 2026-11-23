// swift-tools-version: 6.2
import PackageDescription

let common: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
let mainActor: [SwiftSetting] = common + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "SwiftTunes",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "SwiftTunes", targets: ["SwiftTunes"]),
        .executable(name: "tunes-lifeline", targets: ["tunes-lifeline"]),
    ],
    targets: [
        .target(name: "TunesContract", swiftSettings: common),
        .target(name: "TunesRules", dependencies: ["TunesContract"], swiftSettings: common),
        .target(name: "TunesEngine", dependencies: ["TunesContract", "TunesRules"], swiftSettings: mainActor),
        .target(name: "TunesPanel", dependencies: ["TunesContract"], swiftSettings: common),
        .executableTarget(
            name: "SwiftTunes",
            dependencies: ["TunesContract", "TunesPanel", "TunesEngine"],
            swiftSettings: mainActor
        ),
        .executableTarget(name: "tunes-lifeline"),

        .target(name: "TunesFakes", path: "Tests/TunesFakes", swiftSettings: common),
        .testTarget(name: "TunesRulesTests", dependencies: ["TunesRules"], swiftSettings: common),
        .testTarget(
            name: "TunesEngineTests",
            dependencies: ["TunesEngine", "TunesContract", "TunesFakes", "TunesPanel"],
            swiftSettings: mainActor
        ),
        .testTarget(
            name: "TunesPanelTests",
            dependencies: ["TunesPanel", "TunesContract"],
            resources: [.copy("Fixtures")],
            swiftSettings: common
        ),
    ],
    swiftLanguageModes: [.v6]
)
