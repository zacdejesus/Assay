// swift-tools-version: 6.0
import PackageDescription

// A feature that asks the model to pick two items from a list that go together, in two
// domains (gym, meals), tested with Assay: tapes, an Apple Evaluation, drift and live
// experiments. See README.md.
let package = Package(
    name: "PickTwo",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [.library(name: "PickTwo", targets: ["PickTwo"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "PickTwo", dependencies: [.product(name: "Assay", package: "Assay")]),
        .testTarget(name: "PickTwoTests", dependencies: ["PickTwo", .product(name: "Assay", package: "Assay")],
                    exclude: ["__Cassettes__"]),
    ]
)
