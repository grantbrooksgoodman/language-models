// swift-tools-version: 6.3

/* Native */
import PackageDescription

// MARK: - Package

let package = Package(
    name: "LanguageModels",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "LanguageModels",
            targets: ["LanguageModels"]
        ),
    ],
    targets: [
        .target(
            name: "LanguageModels",
            dependencies: [],
            path: "Sources",
            resources: [.copy("Modules/ChatGPT/Scripts/JavaScript")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
