//
// EnvironmentService.swift
// Xproject
//

import Foundation
import Yams

/// Service for managing environment configurations and xcconfig file generation
public final class EnvironmentService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Configuration Loading

    /// Load environment configuration from env/config.yml
    /// - Parameter workingDirectory: Project working directory
    /// - Returns: Parsed environment configuration
    /// - Throws: EnvironmentError if config file not found or invalid
    public func loadEnvironmentConfig(workingDirectory: String) throws -> EnvironmentConfig {
        let configURL = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("env")
            .appendingPathComponent("config.yml")

        guard fileManager.fileExists(atPath: configURL.path) else {
            throw EnvironmentError.configNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw EnvironmentError.invalidYAML(configURL.path)
        }

        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw EnvironmentError.invalidYAML(configURL.path)
        }

        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(EnvironmentConfig.self, from: yamlString)
        } catch {
            throw EnvironmentError.invalidYAML(configURL.path)
        }
    }

    /// Load environment variables from env/{name}/env.yml
    /// - Parameters:
    ///   - name: Environment name
    ///   - workingDirectory: Project working directory
    /// - Returns: Dictionary of environment variables
    /// - Throws: EnvironmentError if environment not found or invalid YAML
    public func loadEnvironmentVariables(name: String, workingDirectory: String) throws -> [String: Any] {
        let envURL = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("env")
            .appendingPathComponent(name)
            .appendingPathComponent("env.yml")

        guard fileManager.fileExists(atPath: envURL.path) else {
            throw EnvironmentError.environmentNotFound(name)
        }

        let data: Data
        do {
            data = try Data(contentsOf: envURL)
        } catch {
            throw EnvironmentError.invalidYAML(envURL.path)
        }

        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw EnvironmentError.invalidYAML(envURL.path)
        }

        do {
            guard let variables = try Yams.load(yaml: yamlString) as? [String: Any] else {
                throw EnvironmentError.invalidYAML(envURL.path)
            }
            return variables
        } catch {
            throw EnvironmentError.invalidYAML(envURL.path)
        }
    }

    // MARK: - Environment Management

    /// List all available environments
    /// - Parameter workingDirectory: Project working directory
    /// - Returns: Array of environment names
    /// - Throws: EnvironmentError if env directory structure is invalid
    public func listEnvironments(workingDirectory: String) throws -> [String] {
        let envURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent("env")

        guard fileManager.fileExists(atPath: envURL.path) else {
            throw EnvironmentError.invalidEnvironmentDirectory
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: envURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let environments = contents.compactMap { url -> String? in
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    return nil
                }
                return url.lastPathComponent
            }

            return environments
        } catch {
            throw EnvironmentError.invalidEnvironmentDirectory
        }
    }

    /// Get currently active environment
    /// - Parameter workingDirectory: Project working directory
    /// - Returns: Environment name, or nil if none set
    public func getCurrentEnvironment(workingDirectory: String) throws -> String? {
        let currentURL = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("env")
            .appendingPathComponent(".current")

        guard fileManager.fileExists(atPath: currentURL.path) else {
            return nil
        }

        do {
            let content = try String(contentsOf: currentURL, encoding: .utf8)
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Set current environment
    /// - Parameters:
    ///   - name: Environment name to activate
    ///   - workingDirectory: Project working directory
    /// - Throws: EnvironmentError if env directory doesn't exist
    public func setCurrentEnvironment(name: String, workingDirectory: String) throws {
        let envURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent("env")

        guard fileManager.fileExists(atPath: envURL.path) else {
            throw EnvironmentError.invalidEnvironmentDirectory
        }

        let currentURL = envURL.appendingPathComponent(".current")
        try name.write(to: currentURL, atomically: true, encoding: .utf8)
    }

    // MARK: - XCConfig Generation

    /// Generate xcconfig files for all targets
    /// - Parameters:
    ///   - environmentName: Name of environment being activated
    ///   - variables: Environment variables from env.yml
    ///   - workingDirectory: Project working directory
    ///   - dryRun: If true, shows what would be done without executing
    /// - Throws: EnvironmentError or file system errors
    public func generateXCConfigs(
        environmentName: String,
        variables: [String: Any],
        workingDirectory: String,
        dryRun: Bool
    ) throws {
        // Load environment configuration
        let config = try loadEnvironmentConfig(workingDirectory: workingDirectory)

        // Generate xcconfigs for each target
        for target in config.targets {
            // Determine configurations
            let configNames = target.configurations?.keys.sorted() ?? ["debug", "release"]

            // Generate for each configuration
            for configName in configNames {
                // Merge shared variables
                var mergedVars = try resolveVariables(
                    target.sharedVariables,
                    from: variables,
                    bundleIdSuffix: target.bundleIdSuffix
                )

                // Add config-specific variables
                if let configSettings = target.configurations?[configName],
                   let configVars = configSettings.variables {
                    let resolved = try resolveVariables(
                        configVars,
                        from: variables,
                        bundleIdSuffix: target.bundleIdSuffix
                    )
                    mergedVars.merge(resolved) { _, new in new } // Override with config-specific
                }

                // Generate xcconfig file
                let filename = "\(target.name).\(configName).xcconfig"
                let fileURL = URL(fileURLWithPath: workingDirectory)
                    .appendingPathComponent(target.xcconfigPath)
                    .appendingPathComponent(filename)

                try generateXCConfigFile(
                    url: fileURL,
                    variables: mergedVars,
                    environmentName: environmentName,
                    targetName: target.name,
                    configName: configName,
                    dryRun: dryRun
                )
            }
        }
    }

    /// Resolve variable paths to values
    private func resolveVariables(
        _ mapping: [String: String],
        from variables: [String: Any],
        bundleIdSuffix: String?
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]
        let dict = try NestedDictionary(anyYaml: variables)

        for (xcconfigKey, envPath) in mapping {
            guard let value = try dict.value(at: envPath) else {
                // Skip if not found - validation will catch required variables
                continue
            }

            // Apply bundle ID suffix if applicable
            if xcconfigKey == "PRODUCT_BUNDLE_IDENTIFIER", let suffix = bundleIdSuffix {
                resolved[xcconfigKey] = "\(value)\(suffix)"
            } else {
                resolved[xcconfigKey] = value
            }
        }

        return resolved
    }

    /// Generate a single xcconfig file
    private func generateXCConfigFile(
        url: URL,
        variables: [String: String],
        environmentName: String,
        targetName: String,
        configName: String,
        dryRun: Bool
    ) throws {
        var content = """
        // Generated by xp env load \(environmentName)
        // Target: \(targetName)
        // Configuration: \(configName)

        """

        // Sort for consistent output
        for key in variables.keys.sorted() {
            content += "\(key) = \(variables[key]!)\n"
        }

        if dryRun {
            print("Would write to: \(url.path)")
            print(content)
        } else {
            // Ensure directory exists
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            // Write file
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Swift Code Generation

    /// Generate Swift files for all configured outputs
    /// - Parameters:
    ///   - environmentName: Name of environment being activated
    ///   - variables: Environment variables from env.yml
    ///   - workingDirectory: Project working directory
    ///   - dryRun: If true, shows what would be done without executing
    /// - Throws: EnvironmentError or file system errors
    public func generateSwiftFiles(
        environmentName: String,
        variables: [String: Any],
        workingDirectory: String,
        dryRun: Bool
    ) throws {
        // Load environment configuration
        let config = try loadEnvironmentConfig(workingDirectory: workingDirectory)

        // Check if Swift generation is configured
        guard let swiftConfig = config.swiftGeneration else {
            return // Swift generation not configured, skip silently
        }

        // Generate each output file
        for output in swiftConfig.outputs {
            // Determine prefixes based on output type
            var prefixes = output.prefixes
            let outputType = output.type ?? .base

            // Base type automatically includes all root-level variables
            if outputType == .base {
                let rootLevelKeys = variables.keys.filter { !(variables[$0] is [String: Any]) }
                prefixes = rootLevelKeys + prefixes
            }

            // Filter variables by prefix
            let filteredVars = filterVariables(variables, prefixes: prefixes)

            // Convert to Swift properties
            let properties = try convertToSwiftProperties(filteredVars)

            // Generate Swift code
            let swiftCode: String
            switch outputType {
            case .base:
                swiftCode = SwiftTemplates.generateBaseClass(
                    properties: properties,
                    environmentName: environmentName
                )
            case .extension:
                swiftCode = SwiftTemplates.generateExtension(
                    properties: properties,
                    environmentName: environmentName
                )
            }

            // Write file
            let fileURL = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(output.path)

            try writeSwiftFile(
                url: fileURL,
                content: swiftCode,
                dryRun: dryRun
            )
        }
    }

    /// Filter variables by namespace prefixes and convert to camelCase
    /// - Parameters:
    ///   - variables: All environment variables
    ///   - prefixes: Namespace prefixes to include (e.g., ["apps", "features"])
    /// - Returns: Filtered and transformed variables
    private func filterVariables(_ variables: [String: Any], prefixes: [String]) -> [String: Any] {
        var filtered: [String: Any] = [:]

        for prefix in prefixes {
            if let namespaceDict = variables[prefix] as? [String: Any] {
                // This is a namespace (e.g., "apps", "features")
                // Flatten the namespace and add all its variables
                let flattened = flattenDictionary(namespaceDict)
                for (key, value) in flattened {
                    let camelKey = convertToCamelCase(key, prefix: "")
                    filtered[camelKey] = value
                }
            } else if let rootValue = variables[prefix] {
                // This is a root-level variable (e.g., "environment_name", "api_url")
                let camelKey = convertToCamelCase(prefix, prefix: "")
                filtered[camelKey] = rootValue
            }
        }

        return filtered
    }

    /// Flatten nested dictionary to dot notation
    /// - Parameter dict: Nested dictionary
    /// - Parameter prefix: Current key prefix
    /// - Returns: Flattened dictionary with underscore notation
    private func flattenDictionary(_ dict: [String: Any], prefix: String = "") -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in dict {
            let newKey = prefix.isEmpty ? key : "\(prefix)_\(key)"

            if let nestedDict = value as? [String: Any] {
                // Recursively flatten
                let flattened = flattenDictionary(nestedDict, prefix: newKey)
                result.merge(flattened) { _, new in new }
            } else {
                // Terminal value
                result[newKey] = value
            }
        }

        return result
    }

    /// Convert key to camelCase, removing prefix
    /// - Parameters:
    ///   - key: Original key (e.g., "api_url" or "bundle_identifier")
    ///   - prefix: Prefix to remove (not used in namespace-based filtering, kept for compatibility)
    /// - Returns: CamelCase key (e.g., "apiURL", "bundleIdentifier")
    private func convertToCamelCase(_ key: String, prefix: String) -> String {
        // Split by underscore and capitalize
        let components = key.split(separator: "_").map(String.init)
        guard !components.isEmpty else {
            return key
        }

        // First component lowercase, rest capitalized
        var camelCase = components[0].lowercased()
        for component in components.dropFirst() {
            camelCase += component.capitalized
        }

        // Special handling for URL suffix
        // Convert "apiUrl" to "apiURL"
        camelCase = camelCase.replacingOccurrences(
            of: "Url",
            with: "URL",
            options: [],
            range: camelCase.range(of: "Url")
        )

        return camelCase
    }

    /// Convert variables to Swift properties with type inference
    /// - Parameter variables: Filtered variables
    /// - Returns: Array of Swift properties
    /// - Throws: EnvironmentError if type inference fails
    private func convertToSwiftProperties(_ variables: [String: Any]) throws -> [SwiftProperty] {
        var properties: [SwiftProperty] = []

        for (name, value) in variables {
            let (type, stringValue) = inferSwiftType(name: name, value: value)
            properties.append(SwiftProperty(name: name, type: type, value: stringValue))
        }

        return properties
    }

    /// Infer Swift type from value
    /// - Parameters:
    ///   - name: Property name (used for URL detection)
    ///   - value: Value from YAML
    /// - Returns: Tuple of (type, string representation)
    private func inferSwiftType(name: String, value: Any) -> (SwiftType, String) {
        // Check for URL by name suffix
        if name.hasSuffix("URL") || name.hasSuffix("Url") {
            if let stringValue = value as? String {
                return (.url, stringValue)
            }
        }

        // Type inference by value
        if let stringValue = value as? String {
            return (.string, stringValue)
        } else if let intValue = value as? Int {
            return (.int, String(intValue))
        } else if let boolValue = value as? Bool {
            return (.bool, boolValue ? "true" : "false")
        } else if let doubleValue = value as? Double {
            // Treat as int if no decimal part
            if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return (.int, String(Int(doubleValue)))
            }
            // Otherwise treat as string
            return (.string, String(doubleValue))
        }

        // Fallback to string
        return (.string, String(describing: value))
    }

    /// Write Swift file to disk
    private func writeSwiftFile(url: URL, content: String, dryRun: Bool) throws {
        if dryRun {
            print("Would write to: \(url.path)")
            print(content)
        } else {
            // Ensure directory exists
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            // Write file
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Validation

    /// Validate environment configuration
    /// - Parameter workingDirectory: Project working directory
    /// - Throws: EnvironmentError if configuration is invalid
    public func validateEnvironmentConfig(workingDirectory: String) throws {
        // 1. Validate env/ directory structure
        let envURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent("env")
        guard fileManager.fileExists(atPath: envURL.path) else {
            throw EnvironmentError.invalidEnvironmentDirectory
        }

        // 2. Check env/config.yml exists and is valid YAML
        let config = try loadEnvironmentConfig(workingDirectory: workingDirectory)

        // 3. Check xcconfig_path directories exist (FAIL if missing, don't create)
        for target in config.targets {
            let targetURL = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(target.xcconfigPath)
            if !fileManager.fileExists(atPath: targetURL.path) {
                throw EnvironmentError.xcconfigDirectoryNotFound(target.xcconfigPath)
            }
        }

        // 4. Validate all variable paths exist in all environments
        let environments = try listEnvironments(workingDirectory: workingDirectory)
        for envName in environments {
            let variables = try loadEnvironmentVariables(name: envName, workingDirectory: workingDirectory)
            try validateRequiredVariables(config: config, variables: variables, environmentName: envName)
        }
    }

    /// Validate specific environment variables
    /// - Parameters:
    ///   - name: Environment name
    ///   - workingDirectory: Project working directory
    /// - Throws: EnvironmentError if environment is invalid
    public func validateEnvironmentVariables(name: String, workingDirectory: String) throws {
        // 1. Check env/{name}/env.yml exists
        let envURL = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("env")
            .appendingPathComponent(name)
            .appendingPathComponent("env.yml")
        guard fileManager.fileExists(atPath: envURL.path) else {
            throw EnvironmentError.environmentNotFound(name)
        }

        // 2. Load and parse YAML
        _ = try loadEnvironmentVariables(name: name, workingDirectory: workingDirectory)

        // 3. Validate required variables are present
        let config = try loadEnvironmentConfig(workingDirectory: workingDirectory)
        let variables = try loadEnvironmentVariables(name: name, workingDirectory: workingDirectory)
        try validateRequiredVariables(config: config, variables: variables, environmentName: name)
    }

    /// Validate that all required variables are present in environment
    private func validateRequiredVariables(
        config: EnvironmentConfig,
        variables: [String: Any],
        environmentName: String
    ) throws {
        let dict = try NestedDictionary(anyYaml: variables)

        for target in config.targets {
            // Check shared variables
            for (_, envPath) in target.sharedVariables {
                if try dict.value(at: envPath) == nil {
                    throw EnvironmentError.missingVariable(envPath, path: "env/\(environmentName)/env.yml")
                }
            }

            // Check configuration-specific variables
            if let configurations = target.configurations {
                for (_, configSettings) in configurations {
                    if let configVars = configSettings.variables {
                        for (_, envPath) in configVars {
                            if try dict.value(at: envPath) == nil {
                                throw EnvironmentError.missingVariable(envPath, path: "env/\(environmentName)/env.yml")
                            }
                        }
                    }
                }
            }
        }
    }
}
