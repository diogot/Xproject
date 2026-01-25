// swift-tools-version: 6.2
//
// Package.swift
// Xproject
//
import PackageDescription

let settings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency")
]

let package = Package(
    name: "Xproject",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "xp", targets: ["XprojectCLI"]),
        .library(name: "Xproject", targets: ["Xproject"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.0.0"),
        .package(url: "https://github.com/diogot/swift-ejson.git", from: "1.2.0"),
        .package(url: "https://github.com/diogot/swift-pr-reporter.git", from: "1.0.0"),
        .package(url: "https://github.com/diogot/swift-xcresult-parser.git", from: "1.0.5"),
        .package(url: "https://github.com/cpisciotta/xcbeautify", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "XprojectCLI",
            dependencies: [
                "Xproject",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: settings,
            plugins: [
                .plugin(name: "XprojectVersionPlugin")
            ]
        ),
        .target(
            name: "Xproject",
            dependencies: [
                "Yams",
                .product(name: "EJSONKit", package: "swift-ejson"),
                .product(name: "PRReporterKit", package: "swift-pr-reporter"),
                .product(name: "XCResultParser", package: "swift-xcresult-parser"),
                .product(name: "XcbeautifyLib", package: "xcbeautify")
            ],
            swiftSettings: settings
        ),
        .testTarget(
            name: "XprojectTests",
            dependencies: [
                "Xproject"
            ],
            exclude: [
                "TestHelperGuide.md"
            ],
            resources: [
                .copy("Support")
            ],
            swiftSettings: settings
        ),
        .plugin(
            name: "XprojectVersionPlugin",
            capability: .buildTool()
        )
    ]
)
