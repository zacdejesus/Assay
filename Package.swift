// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Assay",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: [
        .library(name: "Assay", targets: ["Assay"]),
        .executable(name: "assay", targets: ["AssayCLI"]),
    ],
    targets: [
        .target(name: "Assay"),
        .executableTarget(name: "AssayCLI", dependencies: ["Assay"]),
        // Tapes are read from disk next to the test files, not bundled as resources.
        .testTarget(name: "AssayTests", dependencies: ["Assay"], exclude: ["__Cassettes__"]),
    ]
)
