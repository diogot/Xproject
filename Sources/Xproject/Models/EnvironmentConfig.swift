//
// EnvironmentConfig.swift
// Xproject
//

import Foundation

// MARK: - Environment Configuration

/// Configuration for environment management system
///
/// Loaded from `env/config.yml`, this defines the targets and their variable mappings
/// for environment-specific xcconfig generation.
public struct EnvironmentConfig: Codable, Sendable {
    /// List of targets to generate xcconfig files for
    public let targets: [EnvironmentTarget]

    /// Swift code generation configuration (optional)
    public let swiftGeneration: SwiftGenerationConfig?

    public init(targets: [EnvironmentTarget], swiftGeneration: SwiftGenerationConfig? = nil) {
        self.targets = targets
        self.swiftGeneration = swiftGeneration
    }

    enum CodingKeys: String, CodingKey {
        case targets
        case swiftGeneration = "swift_generation"
    }
}

// MARK: - Environment Target

/// Configuration for a single build target
public struct EnvironmentTarget: Codable, Sendable {
    /// Target name (e.g., "MyApp", "MyAppWidget")
    public let name: String

    /// Path to directory where xcconfig files will be generated
    /// (relative to working directory)
    public let xcconfigPath: String

    /// Optional bundle ID suffix (e.g., ".widget", ".notification-content")
    /// Applied to PRODUCT_BUNDLE_IDENTIFIER variable
    public let bundleIdSuffix: String?

    /// Shared variables applied to all configurations
    /// Maps xcconfig variable names to environment YAML paths
    /// Example: ["PRODUCT_BUNDLE_IDENTIFIER": "apps.bundle_identifier"]
    public let sharedVariables: [String: String]

    /// Configuration-specific settings (debug, release, etc.)
    /// If nil, generates only debug and release configurations
    public let configurations: [String: ConfigurationSettings]?

    public init(
        name: String,
        xcconfigPath: String,
        bundleIdSuffix: String? = nil,
        sharedVariables: [String: String],
        configurations: [String: ConfigurationSettings]? = nil
    ) {
        self.name = name
        self.xcconfigPath = xcconfigPath
        self.bundleIdSuffix = bundleIdSuffix
        self.sharedVariables = sharedVariables
        self.configurations = configurations
    }

    enum CodingKeys: String, CodingKey {
        case name
        case xcconfigPath = "xcconfig_path"
        case bundleIdSuffix = "bundle_id_suffix"
        case sharedVariables = "shared_variables"
        case configurations
    }
}

// MARK: - Configuration Settings

/// Settings for a specific build configuration (debug, release, etc.)
public struct ConfigurationSettings: Codable, Sendable {
    /// Additional or override variables for this configuration
    /// Maps xcconfig variable names to environment YAML paths
    /// These are merged with the target's shared variables
    public let variables: [String: String]?

    public init(variables: [String: String]? = nil) {
        self.variables = variables
    }
}

// MARK: - Swift Generation Configuration

/// Configuration for Swift code generation from environment variables
public struct SwiftGenerationConfig: Codable, Sendable {
    /// List of output configurations
    public let outputs: [SwiftOutputConfig]

    public init(outputs: [SwiftOutputConfig]) {
        self.outputs = outputs
    }
}

/// Configuration for a single Swift file output
public struct SwiftOutputConfig: Codable, Sendable {
    /// Output file path relative to working directory
    public let path: String

    /// Variable prefixes to include (e.g., ["all", "services"])
    public let prefixes: [String]

    /// Output type: "base" for standalone class, "extension" for class extension
    public let type: SwiftOutputType?

    /// Additional module imports (e.g., ["ModuleA"] when extension needs to import base class module)
    public let imports: [String]

    public init(path: String, prefixes: [String], type: SwiftOutputType? = nil, imports: [String] = []) {
        self.path = path
        self.prefixes = prefixes
        self.type = type
        self.imports = imports
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        prefixes = try container.decode([String].self, forKey: .prefixes)
        type = try container.decodeIfPresent(SwiftOutputType.self, forKey: .type)
        imports = try container.decodeIfPresent([String].self, forKey: .imports) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case prefixes
        case type
        case imports
    }
}

/// Type of Swift output file
public enum SwiftOutputType: String, Codable, Sendable {
    case base
    case `extension`
}

// MARK: - Environment Errors

/// Errors related to environment management
public enum EnvironmentError: Error, LocalizedError {
    case configNotFound
    case environmentNotFound(String)
    case noCurrentEnvironment
    case invalidYAML(path: String, reason: String)
    case missingVariable(String, path: String)
    case invalidEnvironmentDirectory
    case duplicateLeafKey(key: String, namespaces: [String])

    public var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "env/config.yml not found. Run 'xp env validate' to check setup."
        case let .environmentNotFound(name):
            return "Environment '\(name)' not found in env/ directory"
        case .noCurrentEnvironment:
            return "No environment loaded. Run 'xp env load <name>' first."
        case let .invalidYAML(path, reason):
            return """
                Invalid YAML in \(path)

                \(reason)
                """
        case let .missingVariable(varName, path):
            return "Variable '\(varName)' not found at path '\(path)' in environment"
        case .invalidEnvironmentDirectory:
            return "Invalid environment directory structure. env/ directory must exist in project root."
        case let .duplicateLeafKey(key, namespaces):
            return """
                Duplicate leaf key '\(key)' found in namespaces: \(namespaces.joined(separator: ", "))

                Hint: Use separate output files for each namespace, or rename keys to be unique.
                """
        }
    }
}
