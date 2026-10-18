// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lemulip",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FreewheelCore", targets: ["FreewheelCore"]),
        // Distinct product names also keep SwiftPM's intermediate link files
        // separate on the default case-insensitive macOS filesystem.
        .executable(name: "LemulipApp", targets: ["Freewheel"]),
        .executable(name: "lemulip", targets: ["FreewheelCLI"])
    ],
    targets: [
        .target(
            name: "CFreewheelArchive",
            // Some macOS SDKs omit libarchive's public declaration headers.
            // Keep these private to the bridge and use the OS library at runtime.
            cSettings: [.headerSearchPath("LibarchiveHeaders")],
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .target(name: "FreewheelCore", dependencies: ["CFreewheelArchive"]),
        .executableTarget(name: "Freewheel", dependencies: ["FreewheelCore"]),
        .executableTarget(name: "FreewheelCLI", dependencies: ["FreewheelCore"]),
        .testTarget(name: "FreewheelCoreTests", dependencies: ["FreewheelCore"])
    ]
)
