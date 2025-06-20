//
// TestSchemeConfigurationBuilder.swift
// Xproject
//

import Foundation
@testable import Xproject

/// Builder for creating TestSchemeConfiguration instances in tests
public class TestSchemeConfigurationBuilder {
    private var scheme: String = "TestScheme"
    private var buildDestination: String = "generic/platform=iOS Simulator"
    private var testDestinations: [String] = []

    public init() {}

    public func withScheme(_ scheme: String) -> TestSchemeConfigurationBuilder {
        self.scheme = scheme
        return self
    }

    public func withBuildDestination(_ destination: String) -> TestSchemeConfigurationBuilder {
        self.buildDestination = destination
        return self
    }

    public func withTestDestination(_ destination: String) -> TestSchemeConfigurationBuilder {
        self.testDestinations.append(destination)
        return self
    }

    public func withTestDestinations(_ destinations: [String]) -> TestSchemeConfigurationBuilder {
        self.testDestinations = destinations
        return self
    }

    public func build() -> TestSchemeConfiguration {
        return TestSchemeConfiguration(
            scheme: scheme,
            buildDestination: buildDestination,
            testDestinations: testDestinations
        )
    }

    /// Creates an iOS test scheme configuration
    public static func ios(scheme: String = "Nebula") -> TestSchemeConfigurationBuilder {
        return TestSchemeConfigurationBuilder()
            .withScheme(scheme)
            .withBuildDestination("generic/platform=iOS Simulator")
            .withTestDestinations([
                "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro",
                "platform=iOS Simulator,OS=17.0,name=iPhone 15"
            ])
    }

    /// Creates a tvOS test scheme configuration
    public static func tvos(scheme: String = "NebulaTV") -> TestSchemeConfigurationBuilder {
        return TestSchemeConfigurationBuilder()
            .withScheme(scheme)
            .withBuildDestination("generic/platform=tvOS Simulator")
            .withTestDestinations([
                "platform=tvOS Simulator,OS=18.5,name=Apple TV 4K (3rd generation) (at 1080p)"
            ])
    }

    /// Creates a minimal test scheme configuration
    public static func minimal() -> TestSchemeConfiguration {
        return TestSchemeConfigurationBuilder()
            .withTestDestinations(["platform=iOS Simulator,OS=18.5,name=iPhone 16"])
            .build()
    }
}
