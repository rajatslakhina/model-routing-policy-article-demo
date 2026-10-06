// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ModelRoutingPolicy",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ModelRoutingPolicy", targets: ["ModelRoutingPolicy"])
    ],
    targets: [
        .target(name: "ModelRoutingPolicy"),
        .testTarget(name: "ModelRoutingPolicyTests", dependencies: ["ModelRoutingPolicy"])
    ]
)
