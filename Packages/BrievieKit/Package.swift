// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrievieKit",
    defaultLocalization: "nl",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BrievieAPI", targets: ["BrievieAPI"]),
        .library(name: "BrievieCore", targets: ["BrievieCore"]),
        .library(name: "BrievieScan", targets: ["BrievieScan"]),
        .library(name: "BrievieUI", targets: ["BrievieUI"]),
        .library(name: "FeaturePairing", targets: ["FeaturePairing"]),
        .library(name: "FeatureWorkspace", targets: ["FeatureWorkspace"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.12.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.4"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0")
    ],
    targets: [
        .target(
            name: "BrievieAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types")
            ],
            exclude: ["API_VERSION"],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .target(
            name: "BrievieCore",
            dependencies: [
                "BrievieAPI", "BrievieScan", .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "BrievieScan"),
        .target(name: "BrievieUI"),
        .target(
            name: "FeaturePairing",
            dependencies: ["BrievieCore", "BrievieUI"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "FeatureWorkspace",
            dependencies: ["BrievieCore", "BrievieUI"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrievieCoreTests",
            dependencies: ["BrievieCore", "BrievieAPI", "BrievieScan"],
            path: "Tests",
            exclude: ["BrievieScanTests", "FeaturePairingTests", "FeatureWorkspaceTests", "Fixtures/make-certs.sh"],
            sources: ["BrievieCoreTests"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BrievieScanTests",
            dependencies: ["BrievieScan"],
            exclude: ["Fixtures/make-letter.swift"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "FeaturePairingTests", dependencies: ["FeaturePairing", "BrievieCore"]),
        .testTarget(name: "FeatureWorkspaceTests", dependencies: ["FeatureWorkspace", "BrievieCore"])
    ]
)
