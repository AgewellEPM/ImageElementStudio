// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ImageElementStudio",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ImageElementStudio",
            targets: ["ImageElementStudio"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ImageElementStudio",
            path: "Sources/ImageElementStudio"
        ),
        .testTarget(
            name: "ImageElementStudioTests",
            dependencies: ["ImageElementStudio"],
            path: "Tests/ImageElementStudioTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
