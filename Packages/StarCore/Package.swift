// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StarCore",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StarCore", targets: ["StarCore"]),
    ],
    targets: [
        .target(
            name: "StarCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StarCoreTests",
            dependencies: ["StarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
