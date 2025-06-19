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
                try validConfig.validate()
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
                try invalidConfig1.validate()
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
                try invalidConfig2.validate()
            } throws: { error in
                error.localizedDescription.contains("at least one project_path must be specified")
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
                try invalidConfig1.validate()
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
                try invalidConfig2.validate()
            } throws: { error in
                guard let validationError = error as? XprojectConfiguration.ValidationError else {
                    Issue.record("Expected ValidationError, got \(error)")
                    return false
                }
                return validationError.message.contains("at least one project_path must be specified")
            }
        }
    }
}
