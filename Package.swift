// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PaperLibrary",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "PaperLibrary", targets: ["PaperLibrary"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "PaperLibrary",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PaperLibrary",
            exclude: ["Resources"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
