// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prosopon",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "prosopon", targets: ["ProsoponCLI"]),
        .executable(name: "prosopon-review", targets: ["ProsoponReviewApp"]),
        .library(name: "ProsoponCore", targets: ["ProsoponCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ProsoponCore"),
        .target(name: "ProsoponIO", dependencies: ["ProsoponCore"]),
        .target(name: "ProsoponRender", dependencies: ["ProsoponCore"]),
        .target(name: "ProsoponVision", dependencies: ["ProsoponCore", "ProsoponIO"]),
        .target(name: "ProsoponPSD", dependencies: ["ProsoponIO"]),
        .target(name: "ProsoponQA", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .target(name: "ProsoponReview", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender", "ProsoponQA"]),
        .executableTarget(name: "ProsoponReviewApp", dependencies: ["ProsoponReview"]),
        .executableTarget(
            name: "ProsoponCLI",
            dependencies: [
                "ProsoponCore", "ProsoponIO", "ProsoponVision", "ProsoponPSD", "ProsoponRender", "ProsoponQA",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "ProsoponCoreTests", dependencies: ["ProsoponCore"]),
        .testTarget(name: "ProsoponIOTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .testTarget(name: "ProsoponRenderTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .testTarget(name: "ProsoponQATests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponQA"]),
        .testTarget(name: "ProsoponReviewTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponReview"]),
        .testTarget(name: "ProsoponPSDTests", dependencies: ["ProsoponPSD", "ProsoponIO"]),
    ]
)
