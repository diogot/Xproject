//
// XProjectConfigurationBuilder.swift
// XProject
//

import Foundation
@testable import XProject

/// Builder for creating XProjectConfiguration instances in tests
public class XProjectConfigurationBuilder {
    private var appName: String = "TestApp"
    private var workspacePath: String?
    private var projectPaths: [String: String] = [:]
    private var setup: SetupConfiguration?
    private var xcode: XcodeConfiguration?
    private var danger: DangerConfiguration?

    public init() {}

    public func withAppName(_ name: String) -> XProjectConfigurationBuilder {
        self.appName = name
        return self
    }

    public func withWorkspacePath(_ path: String) -> XProjectConfigurationBuilder {
        self.workspacePath = path
        return self
    }

    public func withProjectPath(key: String, path: String) -> XProjectConfigurationBuilder {
        self.projectPaths[key] = path
        return self
    }

    public func withProjectPaths(_ paths: [String: String]) -> XProjectConfigurationBuilder {
        self.projectPaths = paths
        return self
    }

    public func withSetup(_ setup: SetupConfiguration) -> XProjectConfigurationBuilder {
        self.setup = setup
        return self
    }

    public func withBrewSetup(enabled: Bool = true, formulas: [String] = []) -> XProjectConfigurationBuilder {
        self.setup = SetupConfiguration(brew: BrewConfiguration(enabled: enabled, formulas: formulas))
        return self
    }

    public func withXcode(_ xcode: XcodeConfiguration) -> XProjectConfigurationBuilder {
        self.xcode = xcode
        return self
    }

    public func withDanger(_ danger: DangerConfiguration) -> XProjectConfigurationBuilder {
        self.danger = danger
        return self
    }

    public func build() -> XProjectConfiguration {
        return XProjectConfiguration(
            appName: appName,
            workspacePath: workspacePath,
            projectPaths: projectPaths,
            setup: setup,
            xcode: xcode,
            danger: danger
        )
    }

    /// Creates a minimal valid configuration
    public static func minimal() -> XProjectConfiguration {
        return XProjectConfigurationBuilder()
            .withProjectPath(key: "test", path: "Test.xcodeproj")
            .build()
    }

    /// Creates a configuration with full test setup
    public static func fullTestSetup() -> XProjectConfiguration {
        return XProjectConfigurationBuilder()
            .withAppName("FullTestApp")
            .withWorkspacePath("FullTestApp.xcworkspace")
            .withProjectPaths(["ios": "iOS/FullTestApp.xcodeproj", "tvos": "tvOS/FullTestApp.xcodeproj"])
            .withBrewSetup(enabled: true, formulas: ["swiftgen", "swiftlint"])
            .withXcode(XcodeConfigurationBuilder.withTests().build())
            .build()
    }
}
