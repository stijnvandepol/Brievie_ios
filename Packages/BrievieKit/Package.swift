// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrievieKit",
    defaultLocalization: "nl",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BrievieAPI", targets: ["BrievieAPI"]),
        .library(name: "BrievieCore", targets: ["BrievieCore"]),
        .library(name: "BrievieUI", targets: ["BrievieUI"]),
        .library(name: "FeaturePairing", targets: ["FeaturePairing"]),
        .library(name: "FeatureWorkspace", targets: ["FeatureWorkspace"])
    ],
    targets: [
        .target(name: "BrievieAPI"),
        .target(name: "BrievieCore", dependencies: ["BrievieAPI"]),
        .target(name: "BrievieUI"),
        .target(name: "FeaturePairing", dependencies: ["BrievieCore", "BrievieUI"]),
        .target(name: "FeatureWorkspace", dependencies: ["BrievieCore", "BrievieUI"]),
        .testTarget(name: "BrievieCoreTests", dependencies: ["BrievieCore"]),
        .testTarget(name: "FeaturePairingTests", dependencies: ["FeaturePairing"]),
        .testTarget(name: "FeatureWorkspaceTests", dependencies: ["FeatureWorkspace"])
    ]
)
