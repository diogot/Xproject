//
// EnvironmentServiceTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("EnvironmentService Tests")
struct EnvironmentServiceTests {
    // MARK: - Test Helpers

    func createTestEnvironment(
        at workingDir: String,
        config: String,
        environments: [String: String] = [:],
        xcconfigPaths: [String] = []
    ) throws {
        let fm = FileManager.default

        // Clean up if exists
        if fm.fileExists(atPath: workingDir) {
            try fm.removeItem(atPath: workingDir)
        }

        // Create structure
        try fm.createDirectory(atPath: "\(workingDir)/env", withIntermediateDirectories: true)

        // Write config.yml
        try config.write(
            toFile: "\(workingDir)/env/config.yml",
            atomically: true,
            encoding: .utf8
        )

        // Write environment files
        for (envName, envYaml) in environments {
            try fm.createDirectory(atPath: "\(workingDir)/env/\(envName)", withIntermediateDirectories: true)
            try envYaml.write(
                toFile: "\(workingDir)/env/\(envName)/env.yml",
                atomically: true,
                encoding: .utf8
            )
        }

        // Create xcconfig directories
        for path in xcconfigPaths {
            try fm.createDirectory(atPath: "\(workingDir)/\(path)", withIntermediateDirectories: true)
        }
    }

    // MARK: - Configuration Loading Tests

    @Test("Load valid environment config")
    func loadValidConfig() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-load-config"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let config = try service.loadEnvironmentConfig(workingDirectory: workingDir)

        #expect(config.targets.count == 1)
        #expect(config.targets[0].name == "MyApp")
    }

    @Test("Load config with bundle ID suffix")
    func loadConfigWithSuffix() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-bundle-suffix"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: Widget
                xcconfig_path: Config
                bundle_id_suffix: .widget
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let config = try service.loadEnvironmentConfig(workingDirectory: workingDir)

        #expect(config.targets[0].bundleIdSuffix == ".widget")
    }

    @Test("Load config throws when not found")
    func loadConfigNotFound() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-no-config"
        let service = EnvironmentService()

        #expect(throws: EnvironmentError.self) {
            try service.loadEnvironmentConfig(workingDirectory: workingDir)
        }
    }

    // MARK: - Environment Variables Loading Tests

    @Test("Load valid environment variables")
    func loadValidVariables() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-load-vars"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
            ]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        #expect(variables["apps"] != nil)
    }

    @Test("Load variables throws when not found")
    func loadVariablesNotFound() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-no-vars"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()

        #expect(throws: EnvironmentError.self) {
            try service.loadEnvironmentVariables(name: "nonexistent", workingDirectory: workingDir)
        }
    }

    // MARK: - Environment Management Tests

    @Test("List environments")
    func listEnvironments() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-list-envs"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": "apps:\n  bundle_id: com.example.dev",
                "staging": "apps:\n  bundle_id: com.example.staging",
                "production": "apps:\n  bundle_id: com.example.prod"
            ]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let environments = try service.listEnvironments(workingDirectory: workingDir)

        #expect(environments.count == 3)
        #expect(environments.contains("dev"))
        #expect(environments.contains("staging"))
        #expect(environments.contains("production"))
    }

    @Test("Get current environment when not set")
    func getCurrentNotSet() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-current-notset"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let current = try service.getCurrentEnvironment(workingDirectory: workingDir)

        #expect(current == nil)
    }

    @Test("Set and get current environment")
    func setAndGetCurrent() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-set-current"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        try service.setCurrentEnvironment(name: "production", workingDirectory: workingDir)

        let current = try service.getCurrentEnvironment(workingDirectory: workingDir)
        #expect(current == "production")
    }

    // MARK: - XCConfig Generation Tests

    @Test("Generate xcconfigs for simple target")
    func generateSimpleXCConfigs() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-simple"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
                  PRODUCT_NAME: apps.name
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                  name: MyApp Dev
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: false
        )

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: "\(workingDir)/Config/MyApp.debug.xcconfig"))
        #expect(fm.fileExists(atPath: "\(workingDir)/Config/MyApp.release.xcconfig"))

        let debugContent = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.debug.xcconfig"), encoding: .utf8)
        #expect(debugContent.contains("PRODUCT_BUNDLE_IDENTIFIER = com.example.dev"))
        #expect(debugContent.contains("PRODUCT_NAME = MyApp Dev"))
    }

    @Test("Generate xcconfigs with bundle ID suffix")
    func generateWithBundleIdSuffix() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-suffix"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: Widget
                xcconfig_path: Config
                bundle_id_suffix: .widget
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.app
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: false
        )

        let content = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/Widget.debug.xcconfig"), encoding: .utf8)
        #expect(content.contains("PRODUCT_BUNDLE_IDENTIFIER = com.example.app.widget"))
    }

    @Test("Generate xcconfigs with configuration-specific variables")
    func generateWithConfigVariables() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-config-vars"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
                configurations:
                  debug:
                    variables:
                      DEBUG_FLAG: flags.debug
                  release:
                    variables:
                      OPTIMIZATION: flags.optimization
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                flags:
                  debug: "YES"
                  optimization: "-O"
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: false
        )

        let debugContent = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.debug.xcconfig"), encoding: .utf8)
        let releaseContent = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.release.xcconfig"), encoding: .utf8)

        #expect(debugContent.contains("DEBUG_FLAG = YES"))
        #expect(releaseContent.contains("OPTIMIZATION = -O"))
    }

    @Test("Generate xcconfigs dry run does not create files")
    func generateDryRun() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-dryrun"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: true
        )

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: "\(workingDir)/Config/MyApp.debug.xcconfig"))
        #expect(!fm.fileExists(atPath: "\(workingDir)/Config/MyApp.release.xcconfig"))
    }

    // MARK: - Validation Tests

    @Test("Validate valid environment config")
    func validateValid() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-validate-valid"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        try service.validateEnvironmentConfig(workingDirectory: workingDir)
        // No error means validation passed
    }

    @Test("Validate creates xcconfig directory when missing")
    func validateCreatesMissingXCConfigDir() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-validate-no-xcconfig"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
            ]
            // Note: no xcconfigPaths, so Config directory won't exist initially
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let configDir = workingDir + "/Config"

        // Directory should not exist before validation
        #expect(!FileManager.default.fileExists(atPath: configDir))

        // Validation should create the directory
        try service.validateEnvironmentConfig(workingDirectory: workingDir)

        // Directory should now exist
        #expect(FileManager.default.fileExists(atPath: configDir))
    }

    @Test("Validate throws when required variable missing")
    func validateMissingVariable() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-validate-missing-var"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
                  PRODUCT_NAME: apps.name
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
                // Missing apps.name
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()

        #expect(throws: EnvironmentError.self) {
            try service.validateEnvironmentConfig(workingDirectory: workingDir)
        }
    }

    @Test("Validate specific environment succeeds")
    func validateSpecificEnvironment() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-validate-specific"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "production": """
                apps:
                  bundle_id: com.example.prod
                """
            ]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        try service.validateEnvironmentVariables(name: "production", workingDirectory: workingDir)
        // No error means validation passed
    }

    @Test("Validate specific environment throws when not found")
    func validateSpecificNotFound() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-validate-notfound"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()

        #expect(throws: EnvironmentError.self) {
            try service.validateEnvironmentVariables(name: "nonexistent", workingDirectory: workingDir)
        }
    }

    // MARK: - Build Number Injection Tests

    @Test("Generate xcconfigs without build number when nil")
    func generateWithoutBuildNumber() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-no-build"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: false,
            buildNumber: nil
        )

        let content = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.debug.xcconfig"), encoding: .utf8)
        #expect(!content.contains("CURRENT_PROJECT_VERSION"))
    }

    @Test("Generate xcconfigs with build number injection")
    func generateWithBuildNumber() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-build"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_id
            """,
            environments: [
                "dev": """
                apps:
                  bundle_id: com.example.dev
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: false,
            buildNumber: 42
        )

        let debugContent = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.debug.xcconfig"), encoding: .utf8)
        #expect(debugContent.contains("CURRENT_PROJECT_VERSION = 42"))

        let releaseContent = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.release.xcconfig"), encoding: .utf8)
        #expect(releaseContent.contains("CURRENT_PROJECT_VERSION = 42"))
    }

    @Test("Generate xcconfigs strips URL schemes")
    func generateStripsURLSchemes() throws {
        let workingDir = NSTemporaryDirectory() + UUID().uuidString + "/tmp/test-gen-url-strip"

        try createTestEnvironment(
            at: workingDir,
            config: """
            targets:
              - name: MyApp
                xcconfig_path: Config
                shared_variables:
                  API_URL: api_url
                  WEBSITE_URL: website_url
                  PLAIN_VALUE: plain_value
            """,
            environments: [
                "dev": """
                api_url: https://api.example.com
                website_url: http://www.example.com
                plain_value: some-value
                """
            ],
            xcconfigPaths: ["Config"]
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()
        let variables = try service.loadEnvironmentVariables(name: "dev", workingDirectory: workingDir)

        try service.generateXCConfigs(
            environmentName: "dev",
            variables: variables,
            workingDirectory: workingDir,
            dryRun: false
        )

        let content = try String(contentsOf: URL(fileURLWithPath: "\(workingDir)/Config/MyApp.debug.xcconfig"), encoding: .utf8)

        // URL schemes should be stripped
        #expect(content.contains("API_URL = api.example.com"))
        #expect(content.contains("WEBSITE_URL = www.example.com"))

        // Non-URL values should be unchanged
        #expect(content.contains("PLAIN_VALUE = some-value"))

        // Original schemes should not be present
        #expect(!content.contains("https://"))
        #expect(!content.contains("http://"))
    }
}
