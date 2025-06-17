// swift-tools-version: 6.0
//
// Package.swift
// XProject
//
import PackageDescription

let package = Package(
    name: "XProject",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "xp", targets: ["XProjectCLI"]),
        .library(name: "XProject", targets: ["XProject"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "XProjectCLI",
            dependencies: [
                "XProject",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "XProject",
            dependencies: [
                "Yams"
            ]
        ),
        .testTarget(
            name: "XProjectTests",
            dependencies: [
                "XProject"
            ],
            resources: [
                .copy("Support")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
