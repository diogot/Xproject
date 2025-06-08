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
}