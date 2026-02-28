// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ImageElementStudio",
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
            name: "ImageElementStudio"
        ),
        .testTarget(
            name: "ImageElementStudioTests",
            dependencies: ["ImageElementStudio"]
        ),
    ]
)
