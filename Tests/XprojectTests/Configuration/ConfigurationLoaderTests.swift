//
// ConfigurationLoaderTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

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
                guard case ConfigurationError.structureError = error else {
                    Issue.record("Expected ConfigurationError.structureError, got \(error)")
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
            configFileName: "Xproject.yml",
            appName: "Xproject",
            projectName: "TestDiscoveryProject"
        ) {
            let loader = ConfigurationLoader()

            // Should find Xproject.yml in current directory
            #expect(throws: Never.self) {
                try loader.loadConfiguration()
            }

            let config = try loader.loadConfiguration()
            #expect(config.appName == "Xproject")
        }
    }

    @Test("Configuration loader handles file read errors correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithFileReadError() throws {
        // Create a file in a directory that will be removed to simulate read error
        try TestFileHelper.withTemporaryDirectory { tempDir in
            let configURL = tempDir.appendingPathComponent("config.yml")
            let validYAML = """
            app_name: TestApp
            project_path:
              ios: TestApp.xcodeproj
            """

            try validYAML.write(to: configURL, atomically: true, encoding: .utf8)

            // Remove the directory to simulate file access error
            try FileManager.default.removeItem(at: tempDir)

            let loader = ConfigurationLoader()

            #expect {
                try loader.loadConfiguration(from: configURL)
            } throws: { error in
                guard case ConfigurationError.fileReadError(let file, _) = error else {
                    Issue.record("Expected ConfigurationError.fileReadError, got \(error)")
                    return false
                }
                return file == configURL.path
            }
        }
    }

    @Test("Configuration loader handles invalid encoding correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithInvalidEncoding() throws {
        // Create a file with invalid UTF-8 encoding
        try TestFileHelper.withTemporaryDirectory { tempDir in
            let configURL = tempDir.appendingPathComponent("config.yml")

            // Write invalid UTF-8 bytes
            let invalidBytes = Data([0xFF, 0xFE, 0xFD])
            try invalidBytes.write(to: configURL)

            let loader = ConfigurationLoader()

            #expect {
                try loader.loadConfiguration(from: configURL)
            } throws: { error in
                guard case ConfigurationError.invalidEncoding(let file, let encoding) = error else {
                    Issue.record("Expected ConfigurationError.invalidEncoding, got \(error)")
                    return false
                }
                return file == configURL.path && encoding == "UTF-8"
            }
        }
    }

    @Test("Configuration loader handles empty files correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithEmptyFile() throws {
        let loader = ConfigurationLoader()
        let emptyContent = ""

        _ = try TestFileHelper.withTemporaryFile(content: emptyContent) { tempURL in
            #expect {
                try loader.loadConfiguration(from: tempURL)
            } throws: { error in
                guard case ConfigurationError.emptyFile(let file) = error else {
                    Issue.record("Expected ConfigurationError.emptyFile, got \(error)")
                    return false
                }
                return file == tempURL.path
            }
        }
    }

    @Test("Configuration loader handles whitespace-only files correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithWhitespaceOnlyFile() throws {
        let loader = ConfigurationLoader()
        let whitespaceContent = "   \n\t  \n   "

        _ = try TestFileHelper.withTemporaryFile(content: whitespaceContent) { tempURL in
            #expect {
                try loader.loadConfiguration(from: tempURL)
            } throws: { error in
                guard case ConfigurationError.emptyFile(let file) = error else {
                    Issue.record("Expected ConfigurationError.emptyFile, got \(error)")
                    return false
                }
                return file == tempURL.path
            }
        }
    }

    @Test("Configuration loader handles YAML parsing errors correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithYAMLParsingError() throws {
        let loader = ConfigurationLoader()
        // Most YAML parsing errors end up wrapped as DecodingError.dataCorrupted
        // Test that we can handle YAML-related errors regardless of specific wrapping
        let invalidYAMLSyntax = """
        app_name: TestApp
        project_path:
        - invalid indentation should cause structure error
        """

        _ = try TestFileHelper.withTemporaryFile(content: invalidYAMLSyntax) { tempURL in
            #expect {
                try loader.loadConfiguration(from: tempURL)
            } throws: { error in
                // Most YAML errors are wrapped as structureError, which is acceptable
                // This test verifies we handle YAML-related parsing issues
                switch error {
                case ConfigurationError.yamlParsingError(let file, _):
                    return file == tempURL.path
                case ConfigurationError.structureError(let file, _):
                    // YAML parsing errors often manifest as structure errors
                    return file == tempURL.path
                default:
                    Issue.record("Expected ConfigurationError.yamlParsingError or structureError, got \(error)")
                    return false
                }
            }
        }
    }

    @Test("Configuration loader handles YAML structure errors correctly", .tags(.configuration, .errorHandling, .fileSystem))
    func configurationLoaderWithYAMLStructureError() throws {
        let loader = ConfigurationLoader()
        // Valid YAML syntax but invalid structure for XprojectConfiguration
        let invalidStructureYAML = """
        app_name: 123  # Should be string
        project_path: "not a dictionary"  # Should be [String: String]
        """

        _ = try TestFileHelper.withTemporaryFile(content: invalidStructureYAML) { tempURL in
            #expect {
                try loader.loadConfiguration(from: tempURL)
            } throws: { error in
                guard case ConfigurationError.structureError(let file, _) = error else {
                    Issue.record("Expected ConfigurationError.structureError, got \(error)")
                    return false
                }
                return file == tempURL.path
            }
        }
    }
}
