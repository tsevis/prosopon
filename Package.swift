// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prosopon",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "prosopon", targets: ["ProsoponCLI"]),
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
        .executableTarget(
            name: "ProsoponCLI",
            dependencies: [
                "ProsoponCore", "ProsoponIO", "ProsoponVision", "ProsoponPSD", "ProsoponRender",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "ProsoponCoreTests", dependencies: ["ProsoponCore"]),
        .testTarget(name: "ProsoponIOTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .testTarget(name: "ProsoponRenderTests", dependencies: ["ProsoponCore", "ProsoponIO", "ProsoponRender"]),
        .testTarget(name: "ProsoponPSDTests", dependencies: ["ProsoponPSD", "ProsoponIO"]),
    ]
)
