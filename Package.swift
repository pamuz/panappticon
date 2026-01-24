// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Panappticon",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Panappticon",
            path: "Sources/Panappticon",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
