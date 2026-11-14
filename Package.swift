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
    ],
    targets: [
        .target(name: "Assay"),
        .testTarget(name: "AssayTests", dependencies: ["Assay"]),
    ]
)
