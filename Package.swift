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
        // MXShadingContext.h and the node library, for shaders that call stitched functions (e.g. downstream PBR shaders).
        .library(name: "MaterialXMetalShaders", targets: ["MaterialXMetalShaders"]),
        // MetalSprockets integration.
        .library(name: "MetalSprocketsMaterialX", targets: ["MetalSprocketsMaterialX"]),
        .executable(name: "mtlx", targets: ["mtlx"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.3.10")),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.7")),
    ],
    targets: [
        .target(
            name: "MaterialX",
            resources: [.copy("Resources/libraries")]
        ),
        .target(
            name: "MaterialXMetal",
            dependencies: ["MaterialX", "MaterialXMetalShaders"]
        ),
        // The [[stitchable]] node library, compiled by MetalCompilerPlugin like the other MetalSprockets packages.
        .target(
            name: "MaterialXMetalShaders",
            exclude: ["Metal"],
            cSettings: [.define("METAL_COMPILER_PLUGIN_DEBUG", .when(configuration: .debug))],
            plugins: [.plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")]
        ),
        .target(
            name: "MetalSprocketsMaterialX",
            dependencies: [
                "MaterialX",
                "MaterialXMetal",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
            ]
        ),
        // Inspect, validate and stitch .mtlx files.
        .executableTarget(
            name: "mtlx",
            dependencies: [
                "MaterialX",
                "MaterialXMetal",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MaterialXTests", dependencies: ["MaterialX"]),
        .testTarget(
            name: "MaterialXMetalTests",
            dependencies: [
                "MaterialX",
                "MaterialXMetal",
                "MetalSprocketsMaterialX",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage"),
            ],
            // node-coverage.txt is read from the source tree, so it can be regenerated in place.
            exclude: ["Resources/node-coverage.txt"],
            resources: [.copy("Resources/stdlib_genglsl_impl.mtlx"), .copy("Resources/Corpus"), .copy("Resources/Golden Images")]
        ),
    ]
)
