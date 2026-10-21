// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lemulip",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LemulipCore", targets: ["LemulipCore"]),
        // Distinct product names also keep SwiftPM's intermediate link files
        // separate on the default case-insensitive macOS filesystem.
        .executable(name: "LemulipApp", targets: ["Lemulip"]),
        .executable(name: "lemulip", targets: ["LemulipCLI"])
    ],
    targets: [
        .target(
            name: "CLemulipArchive",
            // Some macOS SDKs omit libarchive's public declaration headers.
            // Keep these private to the bridge and use the OS library at runtime.
            cSettings: [.headerSearchPath("LibarchiveHeaders")],
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .target(name: "LemulipCore", dependencies: ["CLemulipArchive"]),
        .executableTarget(name: "Lemulip", dependencies: ["LemulipCore"]),
        .executableTarget(name: "LemulipCLI", dependencies: ["LemulipCore"]),
        .testTarget(name: "LemulipCoreTests", dependencies: ["LemulipCore"])
    ]
)
