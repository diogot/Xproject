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
