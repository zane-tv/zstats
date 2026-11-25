// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZStats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ZStats", targets: ["ZStats"]),
        .library(name: "ZStatKit", targets: ["ZStatKit"]),
        .library(name: "ZStatUI", targets: ["ZStatUI"]),
    ],
    targets: [
        // Metric collection. Deliberately Swift 5 language mode: the collectors are
        // queue-confined by construction (see SamplingCore) rather than by the type
        // system, and the low-level Mach/IOKit code they wrap is not Sendable-clean.
        .target(
            name: "ZStatKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("Metal"),
            ]
        ),
        .target(
            name: "ZStatUI",
            dependencies: ["ZStatKit"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ZStats",
            dependencies: ["ZStatKit", "ZStatUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Named for ZStatKit because that is where almost everything under test
        // lives, but it also links ZStatUI: the pieces of UI logic worth testing
        // are the pure ones (threshold evaluation, render models), and giving them a
        // second test target would split the suite for no gain.
        .testTarget(
            name: "ZStatKitTests",
            dependencies: ["ZStatKit", "ZStatUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
