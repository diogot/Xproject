//
// ConfigurationTests.swift
// XProject
//

// swiftlint:disable prefer_swift_testing_expect
import Foundation
import XCTest
@testable import XProject

final class ConfigurationTests: XCTestCase {
    func testYAMLConfigurationLoading() throws {
        let yamlContent = """
        app_name: TestApp
        workspace_path: TestApp.xcworkspace
        project_path:
          ios: TestApp.xcodeproj
          tvos: TV/TestApp.xcodeproj

        setup:
          brew:
            enabled: true
            formulas:
              - swiftgen
              - swiftlint

        xcode:
          version: "16.4.0"
          build_path: build
          reports_path: reports
          tests:
            schemes:
              - scheme: TestApp
                build_destination: "generic/platform=iOS Simulator"
                test_destinations:
                  - "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro"
        """

        // Create temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-config.yml")

        try yamlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Load configuration
        let format = YAMLConfigurationFormat()
        let config = try format.load(from: tempURL)

        // Verify basic properties
        XCTAssertEqual(config.appName, "TestApp")
        XCTAssertEqual(config.workspacePath, "TestApp.xcworkspace")
        XCTAssertEqual(config.projectPaths["ios"], "TestApp.xcodeproj")
        XCTAssertEqual(config.projectPaths["tvos"], "TV/TestApp.xcodeproj")

        // Verify setup configuration
        XCTAssertNotNil(config.setup)
        XCTAssertEqual(config.setup?.brew?.enabled, true)
        XCTAssertEqual(config.setup?.brew?.formulas, ["swiftgen", "swiftlint"])

        // Note: Xcode configuration will be added when we implement those features
    }

    func testConfigurationValidation() throws {
        // Valid configuration
        let validConfig = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "Package.swift"], // Use existing file
            setup: nil
        )

        XCTAssertNoThrow(try validConfig.validate())

        // Invalid configuration - empty app name
        let invalidConfig1 = XProjectConfiguration(
            appName: "",
            workspacePath: nil,
            projectPaths: ["ios": "Package.swift"],
            setup: nil
        )

        XCTAssertThrowsError(try invalidConfig1.validate()) { error in
            XCTAssertTrue(error.localizedDescription.contains("app_name cannot be empty"))
        }

        // Invalid configuration - no projects
        let invalidConfig2 = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: [:],
            setup: nil
        )

        XCTAssertThrowsError(try invalidConfig2.validate()) { error in
            XCTAssertTrue(error.localizedDescription.contains("at least one project_path must be specified"))
        }

        // Note: Xcode version validation will be added when we implement Xcode features
    }

    func testConfigurationKeyPathAccess() throws {
        let config = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: SetupConfiguration(
                brew: BrewConfiguration(enabled: false)
            )
        )

        // Test value access
        XCTAssertEqual(config.value(for: "app_name") as? String, "TestApp")
        XCTAssertEqual(config.value(for: "workspace_path") as? String, "TestApp.xcworkspace")

        // Test enabled check
        XCTAssertFalse(config.isEnabled("setup.brew"))

        // Test project path access
        XCTAssertEqual(config.projectPath(for: "ios"), "TestApp.xcodeproj")
        XCTAssertNil(config.projectPath(for: "tvos"))
    }

    func testConfigurationLoader() throws {
        let yamlContent = """
        app_name: LoaderTest
        project_path:
          test: Package.swift

        setup:
          brew:
            enabled: true
        """

        // Create temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loader-test.yml")

        try yamlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Test loader
        let loader = ConfigurationLoader()
        let config = try loader.loadConfiguration(from: tempURL)

        XCTAssertEqual(config.appName, "LoaderTest")
        XCTAssertEqual(config.projectPaths["test"], "Package.swift")
        XCTAssertEqual(config.setup?.brew?.enabled, true)
    }

    // MARK: - ConfigurationService Thread Safety Tests

    func testConfigurationServiceThreadSafety() throws {
        let service = ConfigurationService()
        let expectation = XCTestExpectation(description: "Concurrent configuration access")
        expectation.expectedFulfillmentCount = 20

        // Test concurrent access to configuration
        for _ in 0..<20 {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try service.configuration
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent configuration access failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testConfigurationServiceConcurrentReload() throws {
        let service = ConfigurationService()
        let expectation = XCTestExpectation(description: "Concurrent reload operations")
        expectation.expectedFulfillmentCount = 10

        // Load initial configuration
        _ = try service.configuration

        // Test concurrent reload operations
        for _ in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try service.reload()
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent reload failed: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testConfigurationServiceCacheConsistency() throws {
        let service = ConfigurationService()

        // Load configuration multiple times and ensure it's consistent
        let config1 = try service.configuration
        let config2 = try service.configuration
        let config3 = try service.configuration

        XCTAssertEqual(config1.appName, config2.appName)
        XCTAssertEqual(config2.appName, config3.appName)
        XCTAssertEqual(config1.projectPaths.count, config2.projectPaths.count)
        XCTAssertEqual(config2.projectPaths.count, config3.projectPaths.count)
    }

    func testConfigurationServiceClearCache() throws {
        let service = ConfigurationService()

        // Load configuration
        _ = try service.configuration
        XCTAssertTrue(service.isLoaded)

        // Clear cache
        service.clearCache()
        XCTAssertFalse(service.isLoaded)

        // Should be able to load again
        _ = try service.configuration
        XCTAssertTrue(service.isLoaded)
    }

    func testConfigurationServiceConvenienceMethods() throws {
        let service = ConfigurationService()

        // Test convenience methods
        let appName = try service.appName
        XCTAssertEqual(appName, "XProject")

        let projectPaths = try service.projectPaths
        XCTAssertEqual(projectPaths["cli"], "Package.swift")

        let projectPath = try service.projectPath(for: "cli")
        XCTAssertEqual(projectPath, "Package.swift")

        let isBrewEnabled = try service.isEnabled("setup.brew")
        XCTAssertTrue(isBrewEnabled)

        let setup = try service.setup
        XCTAssertNotNil(setup)
        XCTAssertNotNil(setup?.brew)
    }

    func testConfigurationServicePathResolution() throws {
        let service = ConfigurationService()

        // Test path resolution
        let relativePath = service.resolvePath("test/path")
        XCTAssertTrue(relativePath.path.contains("XProject"))
        XCTAssertTrue(relativePath.path.hasSuffix("test/path"))

        let absolutePath = service.resolvePath("/absolute/path")
        XCTAssertEqual(absolutePath.path, "/absolute/path")

        // Test project URL generation
        let projectURL = try service.projectURL(for: "cli")
        XCTAssertNotNil(projectURL)
        XCTAssertTrue(projectURL!.path.hasSuffix("Package.swift"))

        // Test build and reports paths
        let buildPath = service.buildPath()
        XCTAssertTrue(buildPath.path.hasSuffix("build"))

        let reportsPath = service.reportsPath()
        XCTAssertTrue(reportsPath.path.hasSuffix("reports"))
    }

    // MARK: - Configuration Error Handling Tests

    func testConfigurationLoaderWithMissingFile() throws {
        let loader = ConfigurationLoader()
        let nonExistentURL = URL(fileURLWithPath: "/path/that/does/not/exist.yml")

        XCTAssertThrowsError(try loader.loadConfiguration(from: nonExistentURL)) { error in
            // Should throw an error for missing file
            XCTAssertNotNil(error)
        }
    }

    func testConfigurationLoaderWithInvalidYAML() throws {
        let loader = ConfigurationLoader()
        let invalidYAML = """
        app_name: TestApp
        invalid_yaml: [
        malformed structure
        """

        // Create temporary file with invalid YAML
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("invalid-config.yml")

        try invalidYAML.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertThrowsError(try loader.loadConfiguration(from: tempURL)) { error in
            if case ConfigurationError.invalidFormat = error {
                // Expected error type
            } else {
                XCTFail("Expected ConfigurationError.invalidFormat, got \(error)")
            }
        }
    }

    func testConfigurationLoaderWithUnsupportedFormat() throws {
        let loader = ConfigurationLoader()
        let unsupportedURL = URL(fileURLWithPath: "/path/to/config.json")

        XCTAssertThrowsError(try loader.loadConfiguration(from: unsupportedURL)) { error in
            if case ConfigurationError.unsupportedFormat(let ext, _) = error {
                XCTAssertEqual(ext, "json")
            } else {
                XCTFail("Expected ConfigurationError.unsupportedFormat, got \(error)")
            }
        }
    }

    func testConfigurationValidationErrors() throws {
        // Test empty app name validation
        let invalidConfig1 = XProjectConfiguration(
            appName: "",
            workspacePath: nil,
            projectPaths: ["test": "Package.swift"],
            setup: nil
        )

        XCTAssertThrowsError(try invalidConfig1.validate()) { error in
            if let validationError = error as? XProjectConfiguration.ValidationError {
                XCTAssertTrue(validationError.message.contains("app_name cannot be empty"))
            } else {
                XCTFail("Expected ValidationError, got \(error)")
            }
        }

        // Test empty project paths validation
        let invalidConfig2 = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: [:],
            setup: nil
        )

        XCTAssertThrowsError(try invalidConfig2.validate()) { error in
            if let validationError = error as? XProjectConfiguration.ValidationError {
                XCTAssertTrue(validationError.message.contains("at least one project_path must be specified"))
            } else {
                XCTFail("Expected ValidationError, got \(error)")
            }
        }
    }

    // MARK: - Configuration Override Tests

    func testConfigurationEnvironmentOverrides() throws {
        let loader = ConfigurationLoader()

        // Create test configuration
        let yamlContent = """
        app_name: OriginalApp
        project_path:
          test: Package.swift
        """

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("env-test-config.yml")

        try yamlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Set environment variable
        setenv("XPROJECT_APP_NAME", "OverriddenApp", 1)
        defer { unsetenv("XPROJECT_APP_NAME") }

        // Load configuration with overrides
        let config = try loader.loadConfiguration(from: tempURL)

        // Environment override should take precedence
        XCTAssertEqual(config.appName, "OverriddenApp")
        XCTAssertEqual(config.projectPaths["test"], "Package.swift")
    }

    func testConfigurationDefaultDiscovery() throws {
        let loader = ConfigurationLoader()

        // Since we have XProject.yml in the project, this should work
        XCTAssertNoThrow(try loader.loadConfiguration())

        let config = try loader.loadConfiguration()
        XCTAssertEqual(config.appName, "XProject")
    }
}
// swiftlint:enable prefer_swift_testing_expect
