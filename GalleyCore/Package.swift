// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GalleyCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GalleyCore", targets: ["GalleyCore"]),
        .executable(name: "galley-cli", targets: ["galley-cli"]),
    ],
    targets: [
        .target(
            name: "GalleyCore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "galley-cli",
            dependencies: ["GalleyCore"]
        ),
        .testTarget(
            name: "GalleyCoreTests",
            dependencies: ["GalleyCore"]
        ),
    ]
)
