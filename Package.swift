// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "mtats",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MTatsPluginKit", type: .dynamic, targets: ["MTatsPluginKit"]),
        .library(name: "CPUCore", targets: ["CPUCore"]),
        .library(name: "RAMCore", targets: ["RAMCore"]),
        .library(name: "NetworkCore", targets: ["NetworkCore"]),
        .library(name: "GPUCore", targets: ["GPUCore"]),
        .executable(name: "mtats", targets: ["mtats"]),
    ],
    targets: [
        .target(name: "MTatsPluginKit"),
        .target(name: "CPUCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "CPUCoreTests", dependencies: ["CPUCore"]),
        .target(name: "RAMCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "RAMCoreTests", dependencies: ["RAMCore"]),
        .target(name: "NetworkCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "NetworkCoreTests", dependencies: ["NetworkCore"]),
        .target(name: "GPUCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "GPUCoreTests", dependencies: ["GPUCore"]),
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"
        ),
        .executableTarget(name: "mtats", dependencies: ["MTatsPluginKit", "Sparkle"]),
        .testTarget(name: "mtatsTests", dependencies: ["mtats", "MTatsPluginKit"]),
    ]
)
