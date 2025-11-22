//
// XprojectConfiguration.swift
// Xproject
//

// swiftlint:disable file_length

import Foundation

// MARK: - Main Configuration

public struct XprojectConfiguration: Codable, Sendable {
    public let appName: String
    public let workspacePath: String?
    public let projectPaths: [String: String]
    public let setup: SetupConfiguration?
    public let xcode: XcodeConfiguration?
    public let danger: DangerConfiguration?
    public let environment: EnvironmentFeature?
    public let version: VersionConfiguration?
    public let secrets: SecretConfiguration?
    public let provision: ProvisionConfiguration?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case workspacePath = "workspace_path"
        case projectPaths = "project_path"
        case setup
        case xcode
        case danger
        case environment
        case version
        case secrets
        case provision
    }
}

// MARK: - Setup Configuration

public struct SetupConfiguration: Codable, Sendable {
    public let brew: BrewConfiguration?
}

public struct BrewConfiguration: Codable, Sendable {
    public let enabled: Bool?
    public let formulas: [String]?

    public init(enabled: Bool? = nil, formulas: [String]? = nil) {
        self.enabled = enabled
        self.formulas = formulas
    }
}

// MARK: - Environment Configuration

public struct EnvironmentFeature: Codable, Sendable {
    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

// MARK: - Version Configuration

public struct VersionConfiguration: Codable, Sendable {
    public let buildNumberOffset: Int
    public let tagFormat: String?

    enum CodingKeys: String, CodingKey {
        case buildNumberOffset = "build_number_offset"
        case tagFormat = "tag_format"
    }

    public init(buildNumberOffset: Int = 0, tagFormat: String? = nil) {
        self.buildNumberOffset = buildNumberOffset
        self.tagFormat = tagFormat
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
        // Parse keypath like "setup.brew" or "environment" and check if enabled
        let components = keyPath.split(separator: ".")

        // Handle single component paths like "environment"
        if components.count == 1 {
            switch components[0] {
            case "environment":
                return environment?.enabled ?? false
            default:
                return false
            }
        }

        // Handle multi-component paths like "setup.brew"
        guard components.count >= 2 else {
            return false
        }

        switch (components[0], components[1]) {
        case ("setup", "brew"):
            return setup?.brew?.enabled ?? true
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

    func validate(baseDirectory: URL) throws {
        try validateBasicFields()
        try validateProjectPaths(baseDirectory: baseDirectory)
        try validateWorkspacePath(baseDirectory: baseDirectory)

        // Validate Xcode configuration if present
        if let xcode = xcode {
            try validateXcodeConfiguration(xcode)
        }
    }

    private func validateBasicFields() throws {
        if appName.isEmpty {
            throw ValidationError(message: """
                app_name cannot be empty.

                ✅ Example:
                app_name: MyApp
                """)
        }

        if projectPaths.isEmpty {
            throw ValidationError(message: """
                At least one project_path must be specified.

                ✅ Example:
                project_path:
                  ios: MyApp.xcodeproj
                  tvos: MyAppTV/MyAppTV.xcodeproj
                """)
        }
    }

    private func validateProjectPaths(baseDirectory: URL) throws {
        for (target, path) in projectPaths {
            let url: URL
            if path.hasPrefix("/") {
                url = URL(fileURLWithPath: path)
            } else {
                url = baseDirectory.appendingPathComponent(path)
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                // Check for common mistakes
                let suggestions = generatePathSuggestions(for: path, in: baseDirectory, target: target)
                let suggestionText = suggestions.isEmpty ? "" :
                    "\n\n💡 Did you mean:\n" + suggestions.map { "   - \($0)" }.joined(separator: "\n")

                throw ValidationError(message: """
                    Project path for '\(target)' not found: \(path)

                    📁 Searched in: \(url.path)

                    ✅ Make sure the path is correct and the file exists.\(suggestionText)
                    """)
            }
        }
    }

    private func validateWorkspacePath(baseDirectory: URL) throws {
        guard let workspacePath = workspacePath else {
            return
        }

        let url: URL
        if workspacePath.hasPrefix("/") {
            url = URL(fileURLWithPath: workspacePath)
        } else {
            url = baseDirectory.appendingPathComponent(workspacePath)
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            // Check for common mistakes
            let suggestions = generateWorkspaceSuggestions(for: workspacePath, in: baseDirectory)
            let suggestionText = suggestions.isEmpty ? "" :
                "\n\n💡 Did you mean:\n" + suggestions.map { "   - \($0)" }.joined(separator: "\n")

            throw ValidationError(message: """
                Workspace not found: \(workspacePath)

                📁 Searched in: \(url.path)

                ✅ Make sure the path is correct and the file exists.\(suggestionText)
                """)
        }
    }

    private func validateXcodeConfiguration(_ xcode: XcodeConfiguration) throws {
        // Validate test configuration
        if let tests = xcode.tests {
            if tests.schemes.isEmpty {
                throw ValidationError(message: """
                    Test configuration must have at least one scheme.

                    ✅ Example:
                    xcode:
                      tests:
                        schemes:
                          - scheme: MyApp
                            test_destinations:
                              - platform=iOS Simulator,name=iPhone 16
                    """)
            }

            for scheme in tests.schemes {
                if scheme.scheme.isEmpty {
                    throw ValidationError(message: """
                        Scheme name cannot be empty.

                        ✅ Example:
                        schemes:
                          - scheme: MyApp
                            test_destinations:
                              - platform=iOS Simulator,name=iPhone 16
                        """)
                }

                if scheme.testDestinations.isEmpty {
                    throw ValidationError(message: """
                        Test scheme '\(scheme.scheme)' must have at least one test destination.

                        ✅ Example:
                        - scheme: \(scheme.scheme)
                          test_destinations:
                            - platform=iOS Simulator,name=iPhone 16
                            - platform=iOS Simulator,name=iPad Pro (13-inch) (M4)
                        """)
                }
            }
        }

        // Validate release configuration
        if let release = xcode.release {
            for (envName, releaseConfig) in release {
                try validateReleaseConfiguration(envName: envName, config: releaseConfig)
            }
        }
    }

    private func validateReleaseConfiguration(envName: String, config: ReleaseConfiguration) throws {
        try validateReleaseRequiredFields(envName: envName, config: config)
        try validateReleaseSigningConfiguration(envName: envName, config: config)
    }

    // swiftlint:disable:next function_body_length
    private func validateReleaseRequiredFields(envName: String, config: ReleaseConfiguration) throws {
        if config.scheme.isEmpty {
            throw ValidationError(message: """
                Release environment '\(envName)': scheme cannot be empty.

                ✅ Example:
                xcode:
                  release:
                    \(envName):
                      scheme: MyApp
                      output: MyApp
                      destination: iOS
                      type: ios
                """)
        }

        if config.output.isEmpty {
            throw ValidationError(message: """
                Release environment '\(envName)': output cannot be empty.

                ✅ Example:
                xcode:
                  release:
                    \(envName):
                      scheme: \(config.scheme)
                      output: MyApp
                      destination: iOS
                      type: ios
                """)
        }

        if config.destination.isEmpty {
            throw ValidationError(message: """
                Release environment '\(envName)': destination cannot be empty.

                ✅ Example:
                xcode:
                  release:
                    \(envName):
                      scheme: \(config.scheme)
                      output: \(config.output)
                      destination: iOS
                      type: ios

                Common destinations: iOS, tvOS
                """)
        }

        if config.type.isEmpty {
            throw ValidationError(message: """
                Release environment '\(envName)': type cannot be empty.

                ✅ Example:
                xcode:
                  release:
                    \(envName):
                      scheme: \(config.scheme)
                      output: \(config.output)
                      destination: \(config.destination)
                      type: ios

                Common types: ios, appletvos
                """)
        }
    }

    private func validateReleaseSigningConfiguration(envName: String, config: ReleaseConfiguration) throws {
        guard let signing = config.signing, signing.signingStyle == "manual" else {
            return
        }

        if signing.signingCertificate == nil || signing.signingCertificate?.isEmpty == true {
            throw ValidationError(message: """
                Release environment '\(envName)': signingCertificate is required for manual signing.

                ✅ Example:
                xcode:
                  release:
                    \(envName):
                      sign:
                        signingStyle: manual
                        signingCertificate: 'iPhone Distribution'
                        teamID: 'YOUR_TEAM_ID'
                        provisioningProfiles:
                          com.example.app: 'Distribution Profile'
                """)
        }

        if signing.provisioningProfiles == nil || signing.provisioningProfiles?.isEmpty == true {
            throw ValidationError(message: """
                Release environment '\(envName)': provisioningProfiles is required for manual signing.

                ✅ Example:
                xcode:
                  release:
                    \(envName):
                      sign:
                        signingStyle: manual
                        signingCertificate: 'iPhone Distribution'
                        teamID: 'YOUR_TEAM_ID'
                        provisioningProfiles:
                          com.example.app: 'Distribution Profile'
                          com.example.app.extension: 'Extension Profile'
                """)
        }
    }

    private func generatePathSuggestions(for path: String, in baseDirectory: URL, target: String) -> [String] {
        let extensions = ["xcodeproj"]
        let suggestions = scanDirectory(for: extensions, in: baseDirectory)
        return Array(suggestions.prefix(3)) // Limit to 3 suggestions
    }

    private func generateWorkspaceSuggestions(for path: String, in baseDirectory: URL) -> [String] {
        let extensions = ["xcworkspace"]
        let suggestions = scanDirectory(for: extensions, in: baseDirectory)
        return Array(suggestions.prefix(3)) // Limit to 3 suggestions
    }

    private func scanDirectory(for extensions: [String], in baseDirectory: URL) -> [String] {
        var results: [String] = []
        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
            for ext in extensions {
                let matchingFiles = contents.filter { $0.pathExtension == ext }
                for file in matchingFiles {
                    results.append(file.lastPathComponent)
                }
            }
        } catch {
            // Ignore errors when looking for suggestions
        }

        return results
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
