// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Jot",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Jot", targets: ["Jot"]),
    ],
    dependencies: [
        // Updates, like Hun: a signed appcast published with each GitHub release.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "JotKit",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/Fonts")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Jot",
            dependencies: ["JotKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework ships in Jot.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "JotKitTests",
            dependencies: ["JotKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
