// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Jot",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Jot", targets: ["Jot"]),
    ],
    targets: [
        .target(
            name: "JotKit",
            resources: [.copy("Resources/Fonts")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Jot",
            dependencies: ["JotKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "JotKitTests",
            dependencies: ["JotKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
