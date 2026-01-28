// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Panappticon",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/skiptools/swift-sqlcipher.git", from: "1.7.0")
    ],
    targets: [
        .executableTarget(
            name: "Panappticon",
            dependencies: [
                .product(name: "SQLCipher", package: "swift-sqlcipher")
            ],
            path: "Sources/Panappticon",
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .define("SQLITE_HAS_CODEC")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
