//
// ConfigurationTestHelper.swift
// XProject
//

import Foundation
@testable import XProject

/// Shared test helpers for configuration-related tests
public struct ConfigurationTestHelper {
    /// Creates a test configuration service with a predefined test configuration
    public static func createTestConfigurationService() -> ConfigurationService {
        let configPath = Bundle.module.path(forResource: "test-config", ofType: "yml", inDirectory: "Support")!
        let configURL = URL(fileURLWithPath: configPath)
        let configDir = configURL.deletingLastPathComponent()

        // Ensure DummyProject.xcodeproj exists in the same directory as the config
        TestFileHelper.ensureDummyProject(at: configDir)
        return ConfigurationService(customConfigPath: configPath)
    }

    /// Creates a valid test configuration with the specified project path
    public static func createValidTestConfiguration(projectPath: String) -> XProjectConfiguration {
        return XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": projectPath],
            setup: nil,
            xcode: nil,
            danger: nil
        )
    }

    /// Creates a temporary configuration file and service for testing
    public static func withTemporaryConfig<T>(
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

    /// Sets up temporary files for validation testing
    public static func withValidationTestFiles<T>(
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

    /// Creates a test configuration with full Xcode settings
    public static func createTestConfigurationWithXcode() -> XProjectConfiguration {
        let testsConfig = TestsConfiguration(schemes: [
            TestSchemeConfiguration(
                scheme: "Nebula",
                buildDestination: "generic/platform=iOS Simulator",
                testDestinations: [
                    "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro",
                    "platform=iOS Simulator,OS=17.0,name=iPhone 15"
                ]
            ),
            TestSchemeConfiguration(
                scheme: "NebulaTV",
                buildDestination: "generic/platform=tvOS Simulator",
                testDestinations: [
                    "platform=tvOS Simulator,OS=18.5,name=Apple TV 4K (3rd generation) (at 1080p)"
                ]
            )
        ])

        return XProjectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: testsConfig,
                release: nil
            ),
            danger: nil
        )
    }
}

/// Helper for safely changing working directories in tests
public struct WorkingDirectoryHelper {
    public static func withTemporaryWorkingDirectory<T>(
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
