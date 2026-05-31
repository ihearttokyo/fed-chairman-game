// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FedChairmanGame",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FedChairmanCore", targets: ["FedChairmanCore"]),
        .executable(name: "FedChairmanGameNative", targets: ["FedChairmanNativeApp"]),
    ],
    targets: [
        .target(name: "FedChairmanCore"),
        .executableTarget(
            name: "FedChairmanNativeApp",
            dependencies: ["FedChairmanCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FedChairmanCoreTests",
            dependencies: ["FedChairmanCore"]
        ),
    ]
)
