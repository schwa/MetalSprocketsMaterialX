// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsMaterialX",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        // MaterialX document model, parser and the standard node definitions. No Metal.
        .library(name: "MaterialX", targets: ["MaterialX"]),
        // Metal node implementations and the nodegraph → MTLFunctionStitchingGraph compiler.
        .library(name: "MaterialXMetal", targets: ["MaterialXMetal"]),
        // MetalSprockets integration.
        .library(name: "MetalSprocketsMaterialX", targets: ["MetalSprocketsMaterialX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.3.10")),
    ],
    targets: [
        .target(
            name: "MaterialX",
            resources: [.copy("Resources/libraries")]
        ),
        .target(
            name: "MaterialXMetal",
            dependencies: ["MaterialX"],
            resources: [.process("Shaders")]
        ),
        .target(
            name: "MetalSprocketsMaterialX",
            dependencies: [
                "MaterialX",
                "MaterialXMetal",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
            ]
        ),
        .testTarget(name: "MaterialXTests", dependencies: ["MaterialX"]),
        .testTarget(
            name: "MaterialXMetalTests",
            dependencies: ["MaterialX", "MaterialXMetal", "MetalSprocketsMaterialX"],
            resources: [.copy("Resources/stdlib_genglsl_impl.mtlx")]
        ),
    ]
)
