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
        .executableTarget(name: "mtats", dependencies: ["MTatsPluginKit"]),
    ]
)
