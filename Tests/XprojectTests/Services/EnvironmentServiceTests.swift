//
// EnvironmentServiceTests.swift
// XprojectTests
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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-load-config"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-bundle-suffix"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-no-config"
        let service = EnvironmentService()

        #expect(throws: EnvironmentError.self) {
            try service.loadEnvironmentConfig(workingDirectory: workingDir)
        }
    }

    // MARK: - Environment Variables Loading Tests

    @Test("Load valid environment variables")
    func loadValidVariables() throws {
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-load-vars"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-no-vars"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-list-envs"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-current-notset"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-set-current"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-gen-simple"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-gen-suffix"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-gen-config-vars"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-gen-dryrun"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-validate-valid"

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

    @Test("Validate throws when xcconfig directory missing")
    func validateMissingXCConfigDir() throws {
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-validate-no-xcconfig"

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
            // Note: no xcconfigPaths, so Config directory won't exist
        )

        defer { try? FileManager.default.removeItem(atPath: workingDir) }

        let service = EnvironmentService()

        #expect(throws: EnvironmentError.self) {
            try service.validateEnvironmentConfig(workingDirectory: workingDir)
        }
    }

    @Test("Validate throws when required variable missing")
    func validateMissingVariable() throws {
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-validate-missing-var"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-validate-specific"

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
        let workingDir = FileManager.default.currentDirectoryPath + "/tmp/test-validate-notfound"

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
}
