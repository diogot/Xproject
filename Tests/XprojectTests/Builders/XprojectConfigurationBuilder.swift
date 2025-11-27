//
// XprojectConfigurationBuilder.swift
// Xproject
//

import Foundation
@testable import Xproject

/// Builder for creating XprojectConfiguration instances in tests
public class XprojectConfigurationBuilder {
    private var appName: String = "TestApp"
    private var workspacePath: String?
    private var projectPaths: [String: String] = [:]
    private var setup: SetupConfiguration?
    private var xcode: XcodeConfiguration?
    private var danger: DangerConfiguration?
    private var version: VersionConfiguration?

    public init() {}

    public func withAppName(_ name: String) -> XprojectConfigurationBuilder {
        self.appName = name
        return self
    }

    public func withWorkspacePath(_ path: String) -> XprojectConfigurationBuilder {
        self.workspacePath = path
        return self
    }

    public func withProjectPath(key: String, path: String) -> XprojectConfigurationBuilder {
        self.projectPaths[key] = path
        return self
    }

    public func withProjectPaths(_ paths: [String: String]) -> XprojectConfigurationBuilder {
        self.projectPaths = paths
        return self
    }

    public func withSetup(_ setup: SetupConfiguration) -> XprojectConfigurationBuilder {
        self.setup = setup
        return self
    }

    public func withBrewSetup(enabled: Bool? = nil, formulas: [String] = []) -> XprojectConfigurationBuilder {
        self.setup = SetupConfiguration(brew: BrewConfiguration(enabled: enabled, formulas: formulas))
        return self
    }

    public func withXcode(_ xcode: XcodeConfiguration) -> XprojectConfigurationBuilder {
        self.xcode = xcode
        return self
    }

    public func withDanger(_ danger: DangerConfiguration) -> XprojectConfigurationBuilder {
        self.danger = danger
        return self
    }

    public func withVersion(_ version: VersionConfiguration) -> XprojectConfigurationBuilder {
        self.version = version
        return self
    }

    public func build() -> XprojectConfiguration {
        return XprojectConfiguration(
            appName: appName,
            workspacePath: workspacePath,
            projectPaths: projectPaths,
            setup: setup,
            xcode: xcode,
            danger: danger,
            environment: nil,
            version: version,
            secrets: nil,
            provision: nil,
            prReport: nil
        )
    }

    /// Creates a minimal valid configuration
    public static func minimal() -> XprojectConfiguration {
        return XprojectConfigurationBuilder()
            .withProjectPath(key: "test", path: "Test.xcodeproj")
            .build()
    }

    /// Creates a configuration with full test setup
    public static func fullTestSetup() -> XprojectConfiguration {
        return XprojectConfigurationBuilder()
            .withAppName("FullTestApp")
            .withWorkspacePath("FullTestApp.xcworkspace")
            .withProjectPaths(["ios": "iOS/FullTestApp.xcodeproj", "tvos": "tvOS/FullTestApp.xcodeproj"])
            .withBrewSetup(enabled: true, formulas: ["swiftgen", "swiftlint"])
            .withXcode(XcodeConfigurationBuilder.withTests().build())
            .build()
    }
}
