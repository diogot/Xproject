//
// XcodeConfigurationBuilder.swift
// XProject
//

import Foundation
@testable import XProject

/// Builder for creating XcodeConfiguration instances in tests
public class XcodeConfigurationBuilder {
    private var version: String = "16.0"
    private var buildPath: String? = "build"
    private var reportsPath: String? = "reports"
    private var tests: TestsConfiguration?
    private var release: [String: ReleaseConfiguration]?

    public init() {}

    public func withVersion(_ version: String) -> XcodeConfigurationBuilder {
        self.version = version
        return self
    }

    public func withBuildPath(_ path: String?) -> XcodeConfigurationBuilder {
        self.buildPath = path
        return self
    }

    public func withReportsPath(_ path: String?) -> XcodeConfigurationBuilder {
        self.reportsPath = path
        return self
    }

    public func withTests(_ tests: TestsConfiguration) -> XcodeConfigurationBuilder {
        self.tests = tests
        return self
    }

    public func withRelease(_ release: [String: ReleaseConfiguration]) -> XcodeConfigurationBuilder {
        self.release = release
        return self
    }

    public func build() -> XcodeConfiguration {
        return XcodeConfiguration(
            version: version,
            buildPath: buildPath,
            reportsPath: reportsPath,
            tests: tests,
            release: release
        )
    }

    /// Creates a configuration with test schemes
    public static func withTests() -> XcodeConfigurationBuilder {
        let testsConfig = TestsConfiguration(schemes: [
            TestSchemeConfigurationBuilder.ios().build(),
            TestSchemeConfigurationBuilder.tvos().build()
        ])

        return XcodeConfigurationBuilder()
            .withTests(testsConfig)
    }

    /// Creates a minimal Xcode configuration
    public static func minimal() -> XcodeConfiguration {
        return XcodeConfigurationBuilder().build()
    }
}
