//
// ConfigurationTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

// MARK: - Test Helpers

private struct TestFileHelper {
    static func withTemporaryFile<T>(
        content: String,
        fileName: String? = nil,
        fileExtension: String = "yml",
        perform: (URL) throws -> T
    ) throws -> T {
        let fileName = fileName ?? UUID().uuidString
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(fileName).\(fileExtension)")

        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try perform(tempURL)
    }

    static func withTemporaryDirectory<T>(
        perform: (URL) throws -> T
    ) throws -> T {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try perform(tempDir)
    }

    @discardableResult
    static func createDummyProject(in directory: URL, name: String) throws -> URL {
        let projectURL = directory.appendingPathComponent("\(name).xcodeproj")
        try "dummy project".write(to: projectURL, atomically: true, encoding: .utf8)
        return projectURL
    }
}

private struct ConfigurationTestHelper {
    static func createTestConfigurationService() -> ConfigurationService {
        let configPath = Bundle.module.path(forResource: "test-config", ofType: "yml", inDirectory: "Support")!
        return ConfigurationService(customConfigPath: configPath)
    }

    static func withTemporaryConfig<T>(
        appName: String,
        projectName: String,
        additionalYaml: String = "",
        perform: (URL, ConfigurationService) throws -> T
    ) throws -> T {
        return try TestFileHelper.withTemporaryDirectory { tempDir in
            try TestFileHelper.createDummyProject(in: tempDir, name: projectName)

            let yamlContent = """
            app_name: \(appName)
            project_path:
              test: \(projectName).xcodeproj
            \(additionalYaml)
            """

            let configURL = tempDir.appendingPathComponent("config.yml")
            try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

            let configService = ConfigurationService(customConfigPath: configURL.path)

            return try perform(configURL, configService)
        }
    }

    static func withValidationTestFiles<T>(
        appName: String = "ValidationTest",
        projectName: String = "ValidationTestProject",
        perform: (String) throws -> T
    ) throws -> T {
        return try TestFileHelper.withTemporaryDirectory { tempDir in
            try TestFileHelper.createDummyProject(in: tempDir, name: projectName)
            let projectPath = tempDir.appendingPathComponent("\(projectName).xcodeproj").path
            return try perform(projectPath)
        }
    }
}

private struct WorkingDirectoryHelper {
    static func withTemporaryWorkingDirectory<T>(
        configFileName: String = "XProject.yml",
        appName: String = "XProject",
        projectName: String = "TestProject",
        perform: () throws -> T
    ) throws -> T {
        return try TestFileHelper.withTemporaryDirectory { tempDir in
            try TestFileHelper.createDummyProject(in: tempDir, name: projectName)

            let configContent = """
            app_name: \(appName)
            project_path:
              cli: \(projectName).xcodeproj
            """
            let configURL = tempDir.appendingPathComponent(configFileName)
            try configContent.write(to: configURL, atomically: true, encoding: .utf8)

            let originalWorkingDirectory = FileManager.default.currentDirectoryPath
            FileManager.default.changeCurrentDirectoryPath(tempDir.path)
            defer { FileManager.default.changeCurrentDirectoryPath(originalWorkingDirectory) }

            return try perform()
        }
    }
}

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

        let config = try TestFileHelper.withTemporaryFile(content: yamlContent) { tempURL in
            let format = YAMLConfigurationFormat()
            return try format.load(from: tempURL)
        }

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
        try ConfigurationTestHelper.withValidationTestFiles { projectPath in
            // Valid configuration
            let validConfig = XProjectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect(throws: Never.self) {
                try validConfig.validate()
            }

            // Invalid configuration - empty app name
            let invalidConfig1 = XProjectConfiguration(
                appName: "",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: nil,
                danger: nil
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
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig2.validate()
            } throws: { error in
                error.localizedDescription.contains("at least one project_path must be specified")
            }
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
            ),
            xcode: nil,
            danger: nil
        )

        // Test direct property access
        #expect(config.appName == "TestApp")
        #expect(config.workspacePath == "TestApp.xcworkspace")

        // Test enabled check
        #expect(!config.isEnabled("setup.brew"))

        // Test project path access
        #expect(config.projectPath(for: "ios") == "TestApp.xcodeproj")
        #expect(config.projectPath(for: "tvos") == nil)
    }

    @Test("Configuration loader works correctly", .tags(.configuration, .fileSystem, .unit))
    func configurationLoader() throws {
        let additionalYaml = """

        setup:
          brew:
            enabled: true
        """

        try ConfigurationTestHelper.withTemporaryConfig(
            appName: "LoaderTest",
            projectName: "LoaderTestDummyProject",
            additionalYaml: additionalYaml
        ) { configURL, _ in
            let loader = ConfigurationLoader()
            let config = try loader.loadConfiguration(from: configURL)

            #expect(config.appName == "LoaderTest")
            #expect(config.projectPaths["test"] == "LoaderTestDummyProject.xcodeproj")
            #expect(config.setup?.brew?.enabled == true)
        }
    }

    // MARK: - ConfigurationService Thread Safety Tests

    @Test("Configuration service handles concurrent access safely", .tags(.threading, .configuration, .integration))
    func configurationServiceThreadSafety() async throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Test concurrent access to configuration with adaptive behavior for CI
        let taskCount = TestEnvironment.concurrencyTaskCount(local: 10, ci: 5)
        let delay = TestEnvironment.stabilityDelay(local: 0.001, ci: 0.002)

        try await TestEnvironment.withTimeout(seconds: TestEnvironment.operationTimeout()) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<taskCount {
                    group.addTask {
                        _ = try service.configuration
                        // Small delay to reduce contention
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }

                try await group.waitForAll()
            }
        }
    }

    @Test("Configuration service handles concurrent reload operations", .tags(.threading, .configuration, .integration))
    func configurationServiceConcurrentReload() async throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Load initial configuration
        _ = try service.configuration

        // Test concurrent reload operations with adaptive behavior for CI
        let taskCount = TestEnvironment.concurrencyTaskCount(local: 5, ci: 3)
        let delay = TestEnvironment.stabilityDelay(local: 0.002, ci: 0.005)

        try await TestEnvironment.withTimeout(seconds: TestEnvironment.operationTimeout()) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<taskCount {
                    group.addTask {
                        try service.reload()
                        // Small delay to reduce contention
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }

                try await group.waitForAll()
            }
        }
    }

    @Test("Configuration service cache remains consistent", .tags(.configuration, .unit))
    func configurationServiceCacheConsistency() throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

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
        let service = ConfigurationTestHelper.createTestConfigurationService()

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
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Test convenience methods
        let appName = try service.appName
        #expect(appName == "XProject")

        let projectPaths = try service.projectPaths
        #expect(projectPaths["cli"] == "DummyProject.xcodeproj")

        let projectPath = try service.projectPath(for: "cli")
        #expect(projectPath == "DummyProject.xcodeproj")

        let isBrewEnabled = try service.isEnabled("setup.brew")
        #expect(isBrewEnabled)

        let setup = try service.setup
        #expect(setup != nil)
        #expect(setup?.brew != nil)
    }

    @Test("Configuration service path resolution works correctly", .tags(.configuration, .fileSystem, .unit))
    func configurationServicePathResolution() throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Test path resolution
        let relativePath = service.resolvePath("test/path")
        #expect(relativePath.path.hasPrefix("/")) // Should be absolute path
        #expect(relativePath.path.hasSuffix("test/path"))

        let absolutePath = service.resolvePath("/absolute/path")
        #expect(absolutePath.path == "/absolute/path")

        // Test project URL generation
        let projectURL = try service.projectURL(for: "cli")
        #expect(projectURL != nil)
        #expect(projectURL!.path.hasSuffix("DummyProject.xcodeproj"))

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
        try ConfigurationTestHelper.withValidationTestFiles(
            appName: "ValidationErrorTest",
            projectName: "ValidationErrorTestProject"
        ) { projectPath in
            // Test empty app name validation
            let invalidConfig1 = XProjectConfiguration(
                appName: "",
                workspacePath: nil,
                projectPaths: ["test": projectPath],
                setup: nil,
                xcode: nil,
                danger: nil
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
                setup: nil,
                xcode: nil,
                danger: nil
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
    }

    // MARK: - Configuration Override Tests

    @Test("Configuration loader loads base configuration without overrides", .tags(.configuration, .fileSystem, .unit))
    func configurationLoaderBasicBehavior() throws {
        try ConfigurationTestHelper.withTemporaryConfig(
            appName: "BaseApp",
            projectName: "BaseAppDummyProject"
        ) { configURL, _ in
            let loader = ConfigurationLoader()
            let config = try loader.loadConfiguration(from: configURL)

            // Verify base configuration is loaded correctly
            #expect(config.appName == "BaseApp")
            #expect(config.projectPaths["test"] == "BaseAppDummyProject.xcodeproj")
        }
    }

    @Test("Configuration default discovery works correctly", .tags(.configuration, .fileSystem, .integration))
    func configurationDefaultDiscovery() throws {
        try WorkingDirectoryHelper.withTemporaryWorkingDirectory(
            configFileName: "XProject.yml",
            appName: "XProject",
            projectName: "TestDiscoveryProject"
        ) {
            let loader = ConfigurationLoader()

            // Should find XProject.yml in current directory
            #expect(throws: Never.self) {
                try loader.loadConfiguration()
            }

            let config = try loader.loadConfiguration()
            #expect(config.appName == "XProject")
        }
    }
}
