//
// ConfigurationLoaderTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

@Suite("ConfigurationLoader Tests")
struct ConfigurationLoaderTests {
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

        _ = try TestFileHelper.withTemporaryFile(content: invalidYAML, fileName: "invalid-config") { tempURL in
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
