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
    targets: [
        .executableTarget(
            name: "PaperLibrary",
            path: "Sources/PaperLibrary"
        ),
    ],
    swiftLanguageModes: [.v5]
)
