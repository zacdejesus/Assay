// swift-tools-version: 6.0
import PackageDescription

// Everything the TokenSpeed app does, as a package so its tests run with `swift test`.
// Assay is a dependency of the test target only: the library the app links doesn't import it.
let package = Package(
    name: "TokenSpeedCore",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: [
        .library(name: "TokenSpeedCore", targets: ["TokenSpeedCore"]),
    ],
    dependencies: [
        .package(name: "Assay", path: "../../.."),
    ],
    targets: [
        .target(name: "TokenSpeedCore"),
        .testTarget(
            name: "TokenSpeedCoreTests",
            dependencies: ["TokenSpeedCore", .product(name: "Assay", package: "Assay")]
        ),
    ]
)
