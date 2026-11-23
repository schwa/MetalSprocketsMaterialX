// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MaterialXDemoSupport",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "MaterialXDemoSupport", targets: ["MaterialXDemoSupport"]),
    ],
    dependencies: [
        .package(path: "../../../.."),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.3.10")),
    ],
    targets: [
        .target(
            name: "MaterialXDemoSupport",
            dependencies: [
                .product(name: "MetalSprocketsMaterialX", package: "MetalSprocketsMaterialX"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
            ],
            resources: [.copy("Resources/Sample.mtlx")]
        ),
        .testTarget(
            name: "MaterialXDemoSupportTests",
            dependencies: ["MaterialXDemoSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
