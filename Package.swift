// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "omp-ui",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OMPCore", targets: ["OMPCore"]),
        .executable(name: "omp-ui", targets: ["OMPApp"]),
    ],
    targets: [
        .target(name: "OMPCore"),
        .executableTarget(name: "OMPApp", dependencies: ["OMPCore"]),
        .testTarget(name: "OMPCoreTests", dependencies: ["OMPCore"]),
    ]
)
