//
// ConfigurationTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

@Suite("Configuration Tests")
struct ConfigurationTests {
    @Test("YAML configuration loads correctly", .tags(.configuration, .fileSystem, .unit))
    func yamlConfigurationLoading() throws {
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
        #expect(config.appName == "TestApp")
        #expect(config.workspacePath == "TestApp.xcworkspace")
        #expect(config.projectPaths["ios"] == "TestApp.xcodeproj")
        #expect(config.projectPaths["tvos"] == "TV/TestApp.xcodeproj")

        // Verify setup configuration
        #expect(config.setup != nil)
        #expect(config.setup?.brew?.enabled == true)
        #expect(config.setup?.brew?.formulas == ["swiftgen", "swiftlint"])

        // Note: Xcode configuration will be added when we implement those features
    }

    @Test("Configuration validation works correctly", .tags(.configuration, .errorHandling, .unit))
    func configurationValidation() throws {
        // Valid configuration
        let validConfig = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "Package.swift"], // Use existing file
            setup: nil
        )

        #expect(throws: Never.self) {
            try validConfig.validate()
        }

        // Invalid configuration - empty app name
        let invalidConfig1 = XProjectConfiguration(
            appName: "",
            workspacePath: nil,
            projectPaths: ["ios": "Package.swift"],
            setup: nil
        )

        #expect {
            try invalidConfig1.validate()
        } throws: { error in
            error.localizedDescription.contains("app_name cannot be empty")
        }

        // Invalid configuration - no projects
        let invalidConfig2 = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: [:],
            setup: nil
        )

        #expect {
            try invalidConfig2.validate()
        } throws: { error in
            error.localizedDescription.contains("at least one project_path must be specified")
        }

        // Note: Xcode version validation will be added when we implement Xcode features
    }

    @Test("Configuration key path access methods work", .tags(.configuration, .unit))
    func configurationKeyPathAccess() throws {
        let config = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: SetupConfiguration(
                brew: BrewConfiguration(enabled: false)
            )
        )

        // Test value access
        #expect(config.value(for: "app_name") as? String == "TestApp")
        #expect(config.value(for: "workspace_path") as? String == "TestApp.xcworkspace")

        // Test enabled check
        #expect(!config.isEnabled("setup.brew"))

        // Test project path access
        #expect(config.projectPath(for: "ios") == "TestApp.xcodeproj")
        #expect(config.projectPath(for: "tvos") == nil)
    }

    @Test("Configuration loader works correctly", .tags(.configuration, .fileSystem, .unit))
    func configurationLoader() throws {
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

        #expect(config.appName == "LoaderTest")
        #expect(config.projectPaths["test"] == "Package.swift")
        #expect(config.setup?.brew?.enabled == true)
    }

    // MARK: - ConfigurationService Thread Safety Tests

    @Test("Configuration service handles concurrent access safely", .tags(.threading, .configuration, .integration))
    func configurationServiceThreadSafety() async throws {
        let service = ConfigurationService()

        // Test concurrent access to configuration
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try service.configuration
                }
            }
            // Automatically waits for all tasks to complete
        }
    }

    @Test("Configuration service handles concurrent reload operations", .tags(.threading, .configuration, .integration))
    func configurationServiceConcurrentReload() async throws {
        let service = ConfigurationService()

        // Load initial configuration
        _ = try service.configuration

        // Test concurrent reload operations
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try service.reload()
                }
            }
            // Automatically waits for all tasks to complete
        }
    }

    @Test("Configuration service cache remains consistent", .tags(.configuration, .unit))
    func configurationServiceCacheConsistency() throws {
        let service = ConfigurationService()

        // Load configuration multiple times and ensure it's consistent
        let config1 = try service.configuration
        let config2 = try service.configuration
        let config3 = try service.configuration

        #expect(config1.appName == config2.appName)
        #expect(config2.appName == config3.appName)
        #expect(config1.projectPaths.count == config2.projectPaths.count)
        #expect(config2.projectPaths.count == config3.projectPaths.count)
    }

    @Test("Configuration service cache can be cleared", .tags(.configuration, .unit))
    func configurationServiceClearCache() throws {
        let service = ConfigurationService()

        // Load configuration
        _ = try service.configuration
        #expect(service.isLoaded)

        // Clear cache
        service.clearCache()
        #expect(!service.isLoaded)

        // Should be able to load again
        _ = try service.configuration
        #expect(service.isLoaded)
    }

    @Test("Configuration service convenience methods work correctly", .tags(.configuration, .integration))
    func configurationServiceConvenienceMethods() throws {
        let service = ConfigurationService()

        // Test convenience methods
        let appName = try service.appName
        #expect(appName == "XProject")

        let projectPaths = try service.projectPaths
        #expect(projectPaths["cli"] == "Package.swift")

        let projectPath = try service.projectPath(for: "cli")
        #expect(projectPath == "Package.swift")

        let isBrewEnabled = try service.isEnabled("setup.brew")
        #expect(isBrewEnabled)

        let setup = try service.setup
        #expect(setup != nil)
        #expect(setup?.brew != nil)
    }

    @Test("Configuration service path resolution works correctly", .tags(.configuration, .fileSystem, .unit))
    func configurationServicePathResolution() throws {
        let service = ConfigurationService()

        // Test path resolution
        let relativePath = service.resolvePath("test/path")
        #expect(relativePath.path.contains("XProject"))
        #expect(relativePath.path.hasSuffix("test/path"))

        let absolutePath = service.resolvePath("/absolute/path")
        #expect(absolutePath.path == "/absolute/path")

        // Test project URL generation
        let projectURL = try service.projectURL(for: "cli")
        #expect(projectURL != nil)
        #expect(projectURL!.path.hasSuffix("Package.swift"))

        // Test build and reports paths
        let buildPath = service.buildPath()
        #expect(buildPath.path.hasSuffix("build"))

        let reportsPath = service.reportsPath()
        #expect(reportsPath.path.hasSuffix("reports"))
    }

    // MARK: - Configuration Error Handling Tests

    @Test("Configuration loader handles missing files correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithMissingFile() throws {
        let loader = ConfigurationLoader()
        let nonExistentURL = URL(fileURLWithPath: "/path/that/does/not/exist.yml")

        #expect(throws: (any Error).self) {
            try loader.loadConfiguration(from: nonExistentURL)
        }
    }

    @Test("Configuration loader handles invalid YAML correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithInvalidYAML() throws {
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

        #expect {
            try loader.loadConfiguration(from: tempURL)
        } throws: { error in
            guard case ConfigurationError.invalidFormat = error else {
                Issue.record("Expected ConfigurationError.invalidFormat, got \(error)")
                return false
            }
            return true
        }
    }

    @Test("Configuration loader handles unsupported formats correctly", .tags(.configuration, .errorHandling))
    func configurationLoaderWithUnsupportedFormat() throws {
        let loader = ConfigurationLoader()
        let unsupportedURL = URL(fileURLWithPath: "/path/to/config.json")

        #expect {
            try loader.loadConfiguration(from: unsupportedURL)
        } throws: { error in
            guard case ConfigurationError.unsupportedFormat(let ext, _) = error else {
                Issue.record("Expected ConfigurationError.unsupportedFormat, got \(error)")
                return false
            }
            return ext == "json"
        }
    }

    @Test("Configuration validation errors are properly reported", .tags(.configuration, .errorHandling, .unit))
    func configurationValidationErrors() throws {
        // Test empty app name validation
        let invalidConfig1 = XProjectConfiguration(
            appName: "",
            workspacePath: nil,
            projectPaths: ["test": "Package.swift"],
            setup: nil
        )

        #expect {
            try invalidConfig1.validate()
        } throws: { error in
            guard let validationError = error as? XProjectConfiguration.ValidationError else {
                Issue.record("Expected ValidationError, got \(error)")
                return false
            }
            return validationError.message.contains("app_name cannot be empty")
        }

        // Test empty project paths validation
        let invalidConfig2 = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: [:],
            setup: nil
        )

        #expect {
            try invalidConfig2.validate()
        } throws: { error in
            guard let validationError = error as? XProjectConfiguration.ValidationError else {
                Issue.record("Expected ValidationError, got \(error)")
                return false
            }
            return validationError.message.contains("at least one project_path must be specified")
        }
    }

    // MARK: - Configuration Override Tests

    @Test("Configuration loader loads base configuration without overrides", .tags(.configuration, .fileSystem, .unit))
    func configurationLoaderBasicBehavior() throws {
        let loader = ConfigurationLoader()

        // Create test configuration
        let yamlContent = """
        app_name: BaseApp
        project_path:
          test: Package.swift
        """

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("base-config-test.yml")

        try yamlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Load configuration without environment overrides
        let config = try loader.loadConfiguration(from: tempURL)

        // Verify base configuration is loaded correctly
        #expect(config.appName == "BaseApp")
        #expect(config.projectPaths["test"] == "Package.swift")
    }

    @Test("Configuration default discovery works correctly", .tags(.configuration, .fileSystem, .integration))
    func configurationDefaultDiscovery() throws {
        let loader = ConfigurationLoader()

        // Since we have XProject.yml in the project, this should work
        #expect(throws: Never.self) {
            try loader.loadConfiguration()
        }

        let config = try loader.loadConfiguration()
        #expect(config.appName == "XProject")
    }
}
