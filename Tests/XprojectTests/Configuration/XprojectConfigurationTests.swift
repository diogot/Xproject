//
// XprojectConfigurationTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("XprojectConfiguration Tests")
struct XprojectConfigurationTests {
    @Test("Configuration validation works correctly", .tags(.configuration, .errorHandling, .unit))
    func configurationValidation() throws {
        try ConfigurationTestHelper.withValidationTestFiles { projectPath in
            // Valid configuration
            let validConfig = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect(throws: Never.self) {
                try validConfig.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            }

            // Invalid configuration - empty app name
            let invalidConfig1 = XprojectConfiguration(
                appName: "",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig1.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                error.localizedDescription.contains("app_name cannot be empty")
            }

            // Invalid configuration - no projects
            let invalidConfig2 = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: [:],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig2.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                error.localizedDescription.contains("At least one project_path must be specified")
            }
        }

        // Note: Xcode version validation will be added when we implement Xcode features
    }

    @Test("Configuration key path access methods work", .tags(.configuration, .unit))
    func configurationKeyPathAccess() throws {
        let config = XprojectConfiguration(
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

    @Test("Configuration setup.brew enabled defaults to true when not specified", .tags(.configuration, .unit))
    func configurationBrewEnabledDefaultsToTrue() throws {
        // Test with no enabled field specified (should default to true)
        let configWithDefaultEnabled = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: SetupConfiguration(
                brew: BrewConfiguration(formulas: ["swiftgen"])
            ),
            xcode: nil,
            danger: nil
        )

        // Should be enabled by default
        #expect(configWithDefaultEnabled.isEnabled("setup.brew"))

        // Test with explicitly disabled
        let configWithDisabled = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: SetupConfiguration(
                brew: BrewConfiguration(enabled: false, formulas: ["swiftgen"])
            ),
            xcode: nil,
            danger: nil
        )

        // Should be disabled when explicitly set to false
        #expect(!configWithDisabled.isEnabled("setup.brew"))

        // Test with explicitly enabled
        let configWithEnabled = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: SetupConfiguration(
                brew: BrewConfiguration(enabled: true, formulas: ["swiftgen"])
            ),
            xcode: nil,
            danger: nil
        )

        // Should be enabled when explicitly set to true
        #expect(configWithEnabled.isEnabled("setup.brew"))
    }

    @Test("Configuration validation errors are properly reported", .tags(.configuration, .errorHandling, .unit))
    func configurationValidationErrors() throws {
        try ConfigurationTestHelper.withValidationTestFiles(
            appName: "ValidationErrorTest",
            projectName: "ValidationErrorTestProject"
        ) { projectPath in
            // Test empty app name validation
            let invalidConfig1 = XprojectConfiguration(
                appName: "",
                workspacePath: nil,
                projectPaths: ["test": projectPath],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig1.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                return validationError.message.contains("app_name cannot be empty")
            }

            // Test empty project paths validation
            let invalidConfig2 = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: [:],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig2.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                return validationError.message.contains("At least one project_path must be specified")
            }
        }
    }

    @Test("Configuration validation includes example suggestions", .tags(.configuration, .errorHandling, .unit))
    func configurationValidationIncludesExampleSuggestions() throws {
        // Test empty app name includes example
        let invalidConfig1 = XprojectConfiguration(
            appName: "",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: nil,
            danger: nil
        )

        #expect {
            try invalidConfig1.validate(baseDirectory: FileManager.default.temporaryDirectory)
        } throws: { error in
            guard let validationError = error as? XprojectConfiguration.ValidationError else {
                Issue.record("Expected ValidationError, got \(error)")
                return false
            }
            let message = validationError.message
            return message.contains("✅ Example:") &&
                   message.contains("app_name: MyApp")
        }

        // Test empty project paths includes example
        let invalidConfig2 = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: [:],
            setup: nil,
            xcode: nil,
            danger: nil
        )

        #expect {
            try invalidConfig2.validate(baseDirectory: FileManager.default.temporaryDirectory)
        } throws: { error in
            guard let validationError = error as? XprojectConfiguration.ValidationError else {
                Issue.record("Expected ValidationError, got \(error)")
                return false
            }
            let message = validationError.message
            return message.contains("✅ Example:") &&
                   message.contains("project_path:") &&
                   message.contains("ios: MyApp.xcodeproj")
        }
    }

    @Test("Configuration validation includes suggestions for missing project paths", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationValidationIncludesProjectPathSuggestions() throws {
        try TestFileHelper.withTemporaryDirectory { tempDir in
            // Create some .xcodeproj files in the temp directory
            _ = try TestFileHelper.createDummyProject(in: tempDir, name: "SuggestedApp")
            _ = try TestFileHelper.createDummyProject(in: tempDir, name: "AnotherApp")

            let invalidConfig = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["ios": "NonExistentApp.xcodeproj"],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig.validate(baseDirectory: tempDir)
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                let message = validationError.message
                return message.contains("💡 Did you mean:") &&
                       message.contains("SuggestedApp.xcodeproj") &&
                       message.contains("📁 Searched in:")
            }
        }
    }

    @Test("Configuration validation includes suggestions for missing workspace paths", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationValidationIncludesWorkspaceSuggestions() throws {
        try TestFileHelper.withTemporaryDirectory { tempDir in
            // Create some .xcworkspace files in the temp directory
            let workspaceURL1 = tempDir.appendingPathComponent("SuggestedWorkspace.xcworkspace")
            let workspaceURL2 = tempDir.appendingPathComponent("AnotherWorkspace.xcworkspace")
            try "dummy workspace".write(to: workspaceURL1, atomically: true, encoding: .utf8)
            try "dummy workspace".write(to: workspaceURL2, atomically: true, encoding: .utf8)

            // Also create a valid project for the configuration
            _ = try TestFileHelper.createDummyProject(in: tempDir, name: "TestApp")

            let invalidConfig = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: "NonExistentWorkspace.xcworkspace",
                projectPaths: ["ios": "TestApp.xcodeproj"],
                setup: nil,
                xcode: nil,
                danger: nil
            )

            #expect {
                try invalidConfig.validate(baseDirectory: tempDir)
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                let message = validationError.message
                return message.contains("💡 Did you mean:") &&
                       message.contains("SuggestedWorkspace.xcworkspace") &&
                       message.contains("📁 Searched in:")
            }
        }
    }

    @Test("Configuration validation includes examples for empty Xcode test schemes", .tags(.configuration, .errorHandling, .unit))
    func configurationValidationIncludesEmptyXcodeTestSchemesExamples() throws {
        try ConfigurationTestHelper.withValidationTestFiles { projectPath in
            let xcodeConfig = XcodeConfiguration(
                version: "16.4",
                buildPath: nil,
                reportsPath: nil,
                tests: TestsConfiguration(schemes: []),
                release: nil
            )

            let invalidConfig = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: xcodeConfig,
                danger: nil
            )

            #expect {
                try invalidConfig.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                let message = validationError.message
                return message.contains("✅ Example:") &&
                       message.contains("schemes:") &&
                       message.contains("- scheme: MyApp") &&
                       message.contains("test_destinations:")
            }
        }
    }

    @Test("Configuration validation includes examples for empty scheme names", .tags(.configuration, .errorHandling, .unit))
    func configurationValidationIncludesEmptySchemeNameExamples() throws {
        try ConfigurationTestHelper.withValidationTestFiles { projectPath in
            let invalidScheme = TestSchemeConfiguration(
                scheme: "",
                buildDestination: "generic/platform=iOS Simulator",
                testDestinations: ["platform=iOS Simulator,name=iPhone 16"]
            )

            let xcodeConfig = XcodeConfiguration(
                version: "16.4",
                buildPath: nil,
                reportsPath: nil,
                tests: TestsConfiguration(schemes: [invalidScheme]),
                release: nil
            )

            let invalidConfig = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: xcodeConfig,
                danger: nil
            )

            #expect {
                try invalidConfig.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                let message = validationError.message
                return message.contains("✅ Example:") &&
                       message.contains("- scheme: MyApp")
            }
        }
    }

    @Test("Configuration validation includes examples for empty test destinations", .tags(.configuration, .errorHandling, .unit))
    func configurationValidationIncludesEmptyTestDestinationsExamples() throws {
        try ConfigurationTestHelper.withValidationTestFiles { projectPath in
            let schemeWithoutDestinations = TestSchemeConfiguration(
                scheme: "TestApp",
                buildDestination: "generic/platform=iOS Simulator",
                testDestinations: []
            )

            let xcodeConfig = XcodeConfiguration(
                version: "16.4",
                buildPath: nil,
                reportsPath: nil,
                tests: TestsConfiguration(schemes: [schemeWithoutDestinations]),
                release: nil
            )

            let invalidConfig = XprojectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["ios": projectPath],
                setup: nil,
                xcode: xcodeConfig,
                danger: nil
            )

            #expect {
                try invalidConfig.validate(baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent())
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                let message = validationError.message
                return message.contains("✅ Example:") &&
                       message.contains("- scheme: TestApp") &&
                       message.contains("test_destinations:") &&
                       message.contains("platform=iOS Simulator,name=iPhone 16")
            }
        }
    }
}
