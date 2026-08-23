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
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.19.2"),
    ],
    targets: [
        .target(name: "ProsoponCore"),
        .target(name: "ProsoponIO", dependencies: ["ProsoponCore"]),
        .target(name: "ProsoponRender", dependencies: ["ProsoponCore"]),
        .target(name: "ProsoponVision", dependencies: ["ProsoponCore", "ProsoponIO"]),
        .target(
            name: "ProsoponInsight",
            dependencies: [
                "ProsoponCore", "ProsoponIO", "ProsoponVision",
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ]
        ),
        .target(name: "ProsoponPSD", dependencies: ["ProsoponIO"]),
        .target(name: "ProsoponQA", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .target(
            name: "ProsoponPipeline",
            dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender", "ProsoponVision"]
        ),
        .target(
            name: "ProsoponReview",
            dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender", "ProsoponQA", "ProsoponPipeline"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(name: "ProsoponReviewApp", dependencies: ["ProsoponReview"]),
        .executableTarget(
            name: "ProsoponCLI",
            dependencies: [
                "ProsoponCore", "ProsoponIO", "ProsoponVision", "ProsoponPSD", "ProsoponRender",
                "ProsoponQA", "ProsoponInsight", "ProsoponPipeline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "ProsoponCoreTests", dependencies: ["ProsoponCore"]),
        .testTarget(name: "ProsoponRenderTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .testTarget(name: "ProsoponQATests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponQA"]),
        .testTarget(name: "ProsoponReviewTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponReview", "ProsoponQA"]),
        .testTarget(name: "ProsoponPipelineTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponPipeline"]),
        .testTarget(name: "ProsoponInsightTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponInsight"]),
        .testTarget(name: "ProsoponPSDTests", dependencies: ["ProsoponPSD", "ProsoponIO"]),
    ]
)
