//
// EnvironmentService.swift
// Xproject
//

// swiftlint:disable file_length type_body_length

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
            throw EnvironmentError.invalidYAML(path: configURL.path, reason: error.localizedDescription)
        }

        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw EnvironmentError.invalidYAML(path: configURL.path, reason: "File is not valid UTF-8")
        }

        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(EnvironmentConfig.self, from: yamlString)
        } catch let yamlError as YamlError {
            throw EnvironmentError.invalidYAML(path: configURL.path, reason: formatYamlError(yamlError))
        } catch let decodingError as DecodingError {
            throw EnvironmentError.invalidYAML(path: configURL.path, reason: formatDecodingError(decodingError))
        } catch {
            throw EnvironmentError.invalidYAML(path: configURL.path, reason: error.localizedDescription)
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
            throw EnvironmentError.invalidYAML(path: envURL.path, reason: error.localizedDescription)
        }

        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw EnvironmentError.invalidYAML(path: envURL.path, reason: "File is not valid UTF-8")
        }

        do {
            guard let variables = try Yams.load(yaml: yamlString) as? [String: Any] else {
                throw EnvironmentError.invalidYAML(path: envURL.path, reason: "YAML must be a dictionary at root level")
            }
            return variables
        } catch let error as EnvironmentError {
            throw error
        } catch {
            throw EnvironmentError.invalidYAML(path: envURL.path, reason: error.localizedDescription)
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
    ///   - buildNumber: Optional build number to inject as CURRENT_PROJECT_VERSION
    /// - Throws: EnvironmentError or file system errors
    public func generateXCConfigs(
        environmentName: String,
        variables: [String: Any],
        workingDirectory: String,
        dryRun: Bool,
        buildNumber: Int? = nil
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

                // Inject build number if provided
                if let buildNumber = buildNumber {
                    mergedVars["CURRENT_PROJECT_VERSION"] = String(buildNumber)
                }

                // Generate xcconfig file
                let filename = "\(target.name).\(configName).xcconfig"
                let fileURL = URL(fileURLWithPath: workingDirectory)
                    .appendingPathComponent(target.xcconfigPath)
                    .appendingPathComponent(filename)

                let metadata = XCConfigMetadata(
                    environmentName: environmentName,
                    targetName: target.name,
                    configName: configName
                )

                try generateXCConfigFile(
                    url: fileURL,
                    variables: mergedVars,
                    metadata: metadata,
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

    /// Metadata for xcconfig file generation
    private struct XCConfigMetadata {
        let environmentName: String
        let targetName: String
        let configName: String
    }

    /// Strip URL scheme from value for xcconfig compatibility
    /// Returns stripped value if scheme was present, nil otherwise
    private func strippedURLScheme(_ value: String) -> String? {
        if value.hasPrefix("https://") {
            return String(value.dropFirst(8))
        } else if value.hasPrefix("http://") {
            return String(value.dropFirst(7))
        }
        return nil
    }

    /// Generate a single xcconfig file
    private func generateXCConfigFile(
        url: URL,
        variables: [String: String],
        metadata: XCConfigMetadata,
        dryRun: Bool
    ) throws {
        var content = """
        // Generated by xp env load \(metadata.environmentName)
        // Target: \(metadata.targetName)
        // Configuration: \(metadata.configName)

        """

        // Sort for consistent output
        for key in variables.keys.sorted() {
            let value = variables[key] ?? "<nil>"
            if let strippedValue = strippedURLScheme(value) {
                print("Warning: Stripped URL scheme from \(key) for xcconfig compatibility")
                content += "\(key) = \(strippedValue)\n"
            } else {
                content += "\(key) = \(value)\n"
            }
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
                // Merge root-level keys with configured prefixes, removing duplicates
                let combined = rootLevelKeys + prefixes
                prefixes = Array(Set(combined)).sorted()
            }

            // Filter variables by prefix
            let filteredVars = try filterVariables(variables, prefixes: prefixes)

            // Convert to Swift properties
            let properties = try convertToSwiftProperties(filteredVars)

            // Generate Swift code
            let swiftCode: String
            switch outputType {
            case .base:
                swiftCode = SwiftTemplates.generateBaseClass(
                    properties: properties,
                    environmentName: environmentName,
                    imports: output.imports
                )
            case .extension:
                swiftCode = SwiftTemplates.generateExtension(
                    properties: properties,
                    environmentName: environmentName,
                    imports: output.imports
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
    ///
    /// Prefixes can be:
    /// - Top-level namespaces (e.g., "apps", "features")
    /// - Nested namespace keys that exist under other top-level namespaces (e.g., "ios" under "apps")
    ///
    /// When a prefix like "ios" exists as a nested key under another prefix like "apps",
    /// the "apps" namespace will exclude "ios" from its flattening, and "ios" will be
    /// processed separately to get only its specific variables.
    ///
    /// - Returns: Filtered and transformed variables
    /// - Throws: `EnvironmentError.duplicateLeafKey` if the same leaf key appears in multiple namespaces
    private func filterVariables(_ variables: [String: Any], prefixes: [String]) throws -> [String: Any] {
        var filtered: [String: Any] = [:]
        var sources: [String: String] = [:]
        let prefixSet = Set(prefixes)
        let topLevelNamespaces = collectTopLevelNamespaces(from: variables, prefixes: prefixes)

        for prefix in prefixes.sorted() {
            if let namespaceDict = variables[prefix] as? [String: Any] {
                let flattened = try flattenDictionary(namespaceDict, excludingKeys: prefixSet, parentPath: prefix)
                try mergeFlattened(flattened, into: &filtered, sources: &sources)
            } else {
                try processNestedPrefix(prefix, topLevelNamespaces: topLevelNamespaces, prefixSet: prefixSet,
                                        filtered: &filtered, sources: &sources)
            }
            try addRootLevelScalar(prefix, from: variables, to: &filtered, sources: &sources)
        }
        return filtered
    }

    private func collectTopLevelNamespaces(from variables: [String: Any], prefixes: [String]) -> [String: [String: Any]] {
        var topLevelNamespaces: [String: [String: Any]] = [:]
        for prefix in prefixes.sorted() {
            if let namespaceDict = variables[prefix] as? [String: Any] {
                topLevelNamespaces[prefix] = namespaceDict
            }
        }
        return topLevelNamespaces
    }

    private func mergeFlattened(
        _ flattened: [String: (value: Any, source: String)],
        into filtered: inout [String: Any],
        sources: inout [String: String]
    ) throws {
        for (key, data) in flattened.sorted(by: { $0.key < $1.key }) {
            let camelKey = convertToCamelCase(key, prefix: "")
            if let existingSource = sources[camelKey] {
                throw EnvironmentError.duplicateLeafKey(key: key, namespaces: [existingSource, data.source].sorted())
            }
            filtered[camelKey] = data.value
            sources[camelKey] = data.source
        }
    }

    private func processNestedPrefix(
        _ prefix: String,
        topLevelNamespaces: [String: [String: Any]],
        prefixSet: Set<String>,
        filtered: inout [String: Any],
        sources: inout [String: String]
    ) throws {
        for (namespaceName, namespaceDict) in topLevelNamespaces.sorted(by: { $0.key < $1.key }) {
            if let nestedDict = namespaceDict[prefix] as? [String: Any] {
                let parentPath = "\(namespaceName).\(prefix)"
                let flattened = try flattenDictionary(nestedDict, excludingKeys: prefixSet, parentPath: parentPath)
                try mergeFlattened(flattened, into: &filtered, sources: &sources)
                break
            }
        }
    }

    private func addRootLevelScalar(
        _ prefix: String,
        from variables: [String: Any],
        to filtered: inout [String: Any],
        sources: inout [String: String]
    ) throws {
        guard let rootValue = variables[prefix], !(rootValue is [String: Any]) else {
            return
        }
        let camelKey = convertToCamelCase(prefix, prefix: "")
        if let existingSource = sources[camelKey] {
            throw EnvironmentError.duplicateLeafKey(key: prefix, namespaces: [existingSource, prefix].sorted())
        }
        filtered[camelKey] = rootValue
        sources[camelKey] = prefix
    }

    /// Flatten nested dictionary, keeping only leaf key names
    /// - Parameters:
    ///   - dict: Nested dictionary
    ///   - excludingKeys: Keys to skip during flattening (used to prevent mixing platform-specific variables)
    ///   - parentPath: The path to the current dictionary (for error reporting)
    /// - Returns: Flattened dictionary with leaf keys and their source paths
    /// - Throws: `EnvironmentError.duplicateLeafKey` if the same leaf key appears in multiple namespaces
    private func flattenDictionary(
        _ dict: [String: Any],
        excludingKeys: Set<String> = [],
        parentPath: String = ""
    ) throws -> [String: (value: Any, source: String)] {
        var result: [String: (value: Any, source: String)] = [:]

        // Sort keys for deterministic iteration order
        let sortedKeys = dict.keys.sorted()

        for key in sortedKeys {
            guard let value = dict[key] else { continue }

            // Skip keys that should be handled by other prefixes
            if excludingKeys.contains(key) {
                continue
            }

            let currentPath = parentPath.isEmpty ? key : "\(parentPath).\(key)"

            if let nestedDict = value as? [String: Any] {
                // Recursively flatten, passing through the exclusion set
                let flattened = try flattenDictionary(nestedDict, excludingKeys: excludingKeys, parentPath: currentPath)
                for (leafKey, leafData) in flattened.sorted(by: { $0.key < $1.key }) {
                    if let existing = result[leafKey] {
                        throw EnvironmentError.duplicateLeafKey(
                            key: leafKey,
                            namespaces: [existing.source, leafData.source].sorted()
                        )
                    }
                    result[leafKey] = leafData
                }
            } else {
                // Terminal value - use only the leaf key
                if let existing = result[key] {
                    throw EnvironmentError.duplicateLeafKey(
                        key: key,
                        namespaces: [existing.source, currentPath].sorted()
                    )
                }
                result[key] = (value: value, source: currentPath)
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
            with: "URL"
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

        // 3. Ensure xcconfig_path directories exist (create if missing)
        for target in config.targets {
            let targetURL = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(target.xcconfigPath)
            if !fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
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
            for (_, envPath) in target.sharedVariables where try dict.value(at: envPath) == nil {
                throw EnvironmentError.missingVariable(envPath, path: "env/\(environmentName)/env.yml")
            }

            // Check configuration-specific variables
            if let configurations = target.configurations {
                for (_, configSettings) in configurations {
                    if let configVars = configSettings.variables {
                        for (_, envPath) in configVars where try dict.value(at: envPath) == nil {
                            throw EnvironmentError.missingVariable(envPath, path: "env/\(environmentName)/env.yml")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error Formatting

    private func formatYamlError(_ yamlError: YamlError) -> String {
        switch yamlError {
        case let .scanner(_, problem, mark, _):
            return "Syntax error at line \(mark.line + 1), column \(mark.column + 1): \(problem)"
        case let .parser(_, problem, mark, _):
            return "Parse error at line \(mark.line + 1), column \(mark.column + 1): \(problem)"
        case let .composer(_, problem, mark, _):
            return "Composition error at line \(mark.line + 1), column \(mark.column + 1): \(problem)"
        default:
            return yamlError.localizedDescription
        }
    }

    private func formatDecodingError(_ decodingError: DecodingError) -> String {
        switch decodingError {
        case let .typeMismatch(type, context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let pathDescription = path.isEmpty ? "root" : "'\(path)'"
            return "Type mismatch at \(pathDescription): expected \(type). \(context.debugDescription)"
        case let .valueNotFound(type, context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let pathDescription = path.isEmpty ? "root" : "'\(path)'"
            return "Missing value at \(pathDescription): expected \(type)"
        case let .keyNotFound(key, context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let pathDescription = path.isEmpty ? "root" : "'\(path)'"
            return "Missing required key '\(key.stringValue)' at \(pathDescription)"
        case let .dataCorrupted(context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let pathDescription = path.isEmpty ? "root" : "'\(path)'"
            return "Invalid data at \(pathDescription): \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}
// swiftlint:enable type_body_length
