//
// XprojectConfiguration.swift
// Xproject
//

import Foundation

// MARK: - Main Configuration

public struct XprojectConfiguration: Codable, Sendable {
    public let appName: String
    public let workspacePath: String?
    public let projectPaths: [String: String]
    public let setup: SetupConfiguration?
    public let xcode: XcodeConfiguration?
    public let danger: DangerConfiguration?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case workspacePath = "workspace_path"
        case projectPaths = "project_path"
        case setup
        case xcode
        case danger
    }
}

// MARK: - Setup Configuration

public struct SetupConfiguration: Codable, Sendable {
    public let brew: BrewConfiguration?
}

public struct BrewConfiguration: Codable, Sendable {
    public let enabled: Bool
    public let formulas: [String]?

    public init(enabled: Bool, formulas: [String]? = nil) {
        self.enabled = enabled
        self.formulas = formulas
    }
}

// MARK: - Configuration Extensions

public extension XprojectConfiguration {
    /// Get project path for a specific target
    func projectPath(for target: String) -> String? {
        return projectPaths[target]
    }

    /// Check if a component is enabled
    func isEnabled(_ keyPath: String) -> Bool {
        // Parse keypath like "setup.brew" and check if enabled
        let components = keyPath.split(separator: ".")
        guard components.count >= 2 else {
            return false
        }

        switch (components[0], components[1]) {
        case ("setup", "brew"):
            return setup?.brew?.enabled ?? false
        default:
            return false
        }
    }

    /// Get project or workspace argument for xcodebuild
    func projectOrWorkspace() -> String {
        if let workspacePath = workspacePath {
            return "-workspace '\(workspacePath)'"
        } else if let firstProjectPath = projectPaths.values.first {
            return "-project '\(firstProjectPath)'"
        } else {
            return ""
        }
    }

    /// Get build path (from environment or config)
    func buildPath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["ARTIFACTS_PATH"] {
            return envPath
        }
        return xcode?.buildPath ?? "build"
    }

    /// Get reports path (from environment or config)
    func reportsPath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["TEST_REPORTS_PATH"] {
            return envPath
        }
        return xcode?.reportsPath ?? "reports"
    }
}

// MARK: - Validation

public extension XprojectConfiguration {
    struct ValidationError: Error, LocalizedError, Sendable {
        let message: String

        public var errorDescription: String? {
            return message
        }
    }

    func validate() throws {
        try validate(baseDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    func validate(baseDirectory: URL) throws {
        if appName.isEmpty {
            throw ValidationError(message: "app_name cannot be empty")
        }

        if projectPaths.isEmpty {
            throw ValidationError(message: "at least one project_path must be specified")
        }

        // Validate project paths exist
        for (target, path) in projectPaths {
            let url: URL
            if path.hasPrefix("/") {
                url = URL(fileURLWithPath: path)
            } else {
                url = baseDirectory.appendingPathComponent(path)
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                throw ValidationError(message: "project path for '\(target)' not found: \(path)")
            }
        }

        // Validate workspace path if specified
        if let workspacePath = workspacePath {
            let url: URL
            if workspacePath.hasPrefix("/") {
                url = URL(fileURLWithPath: workspacePath)
            } else {
                url = baseDirectory.appendingPathComponent(workspacePath)
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                throw ValidationError(message: "workspace not found: \(workspacePath)")
            }
        }
    }
}

// MARK: - Xcode Configuration

public struct XcodeConfiguration: Codable, Sendable {
    public let version: String
    public let buildPath: String?
    public let reportsPath: String?
    public let tests: TestsConfiguration?
    public let release: [String: ReleaseConfiguration]?

    enum CodingKeys: String, CodingKey {
        case version
        case buildPath = "build_path"
        case reportsPath = "reports_path"
        case tests
        case release
    }
}

public struct TestsConfiguration: Codable, Sendable {
    public let schemes: [TestSchemeConfiguration]
}

public struct TestSchemeConfiguration: Codable, Sendable {
    public let scheme: String
    public let buildDestination: String
    public let testDestinations: [String]

    enum CodingKeys: String, CodingKey {
        case scheme
        case buildDestination = "build_destination"
        case testDestinations = "test_destinations"
    }
}

public struct ReleaseConfiguration: Codable, Sendable {
    public let scheme: String
    public let configuration: String?
    public let output: String
    public let destination: String
    public let type: String
    public let appStoreAccount: String?
    public let signing: SigningConfiguration?

    enum CodingKeys: String, CodingKey {
        case scheme
        case configuration
        case output
        case destination
        case type
        case appStoreAccount = "app_store_account"
        case signing = "sign"
    }
}

public struct SigningConfiguration: Codable, Sendable {
    public let signingCertificate: String?
    public let teamID: String?
    public let signingStyle: String?
    public let provisioningProfiles: [String: String]?

    enum CodingKeys: String, CodingKey {
        case signingCertificate
        case teamID
        case signingStyle
        case provisioningProfiles
    }
}

// MARK: - Danger Configuration

public struct DangerConfiguration: Codable, Sendable {
    public let dangerfilePaths: DangerfilePaths?

    enum CodingKeys: String, CodingKey {
        case dangerfilePaths = "dangerfile_paths"
    }
}

public struct DangerfilePaths: Codable, Sendable {
    public let preTest: String?
    public let build: String?
    public let test: String?
    public let postTest: String?

    enum CodingKeys: String, CodingKey {
        case preTest = "pre_test"
        case build
        case test
        case postTest = "post_test"
    }
}
