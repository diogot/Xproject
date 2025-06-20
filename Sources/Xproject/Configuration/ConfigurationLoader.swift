//
// ConfigurationLoader.swift
// Xproject
//

import Foundation
import Yams

// MARK: - Configuration Format Protocol

public protocol ConfigurationFormat: Sendable {
    func load(from url: URL) throws -> XprojectConfiguration
    var supportedExtensions: [String] { get }
}

// MARK: - YAML Configuration Format

public struct YAMLConfigurationFormat: ConfigurationFormat {
    public let supportedExtensions = ["yml", "yaml"]

    public init() {}

    public func load(from url: URL) throws -> XprojectConfiguration {
        let data = try Data(contentsOf: url)
        let yamlString = String(data: data, encoding: .utf8) ?? ""

        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(XprojectConfiguration.self, from: yamlString)
        } catch {
            throw ConfigurationError.invalidFormat(
                format: "YAML",
                file: url.path,
                underlyingError: error
            )
        }
    }
}

// MARK: - Configuration Loader

public final class ConfigurationLoader: Sendable {
    private let formats: [ConfigurationFormat]

    public init(formats: [ConfigurationFormat] = [YAMLConfigurationFormat()]) {
        self.formats = formats
    }

    /// Load configuration from default locations
    public func loadConfiguration() throws -> XprojectConfiguration {
        let (config, _) = try loadConfigurationWithPath()
        return config
    }

    /// Load configuration from default locations, returning both config and file path
    public func loadConfigurationWithPath() throws -> (XprojectConfiguration, String) {
        let possiblePaths = [
            "Xproject.yml",
            "Xproject.yaml",
            "rake-config.yml",    // Legacy compatibility
            "rake-config.yaml"    // Legacy compatibility
        ]

        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                let config = try loadConfiguration(from: url)
                return (config, path)
            }
        }

        throw ConfigurationError.noConfigurationFound(searchPaths: possiblePaths)
    }

    /// Load configuration from specific file
    public func loadConfiguration(from url: URL) throws -> XprojectConfiguration {
        let fileExtension = url.pathExtension.lowercased()

        guard let format = formats.first(where: { $0.supportedExtensions.contains(fileExtension) }) else {
            throw ConfigurationError.unsupportedFormat(
                extension: fileExtension,
                supportedExtensions: formats.flatMap { $0.supportedExtensions }
            )
        }

        do {
            let configuration = try format.load(from: url)
            try configuration.validate(baseDirectory: url.deletingLastPathComponent())
            return configuration
        } catch let error as XprojectConfiguration.ValidationError {
            throw ConfigurationError.validation(file: url.path, error: error)
        } catch {
            throw error
        }
    }

    /// Load configuration with layered overrides
    public func loadConfigurationWithOverrides() throws -> XprojectConfiguration {
        let (config, _) = try loadConfigurationWithOverridesAndPath()
        return config
    }

    /// Load configuration with layered overrides, returning both config and file path
    public func loadConfigurationWithOverridesAndPath() throws -> (XprojectConfiguration, String) {
        let (baseConfig, configPath) = try loadConfigurationWithPath()
        var configuration = baseConfig

        // Try to load local overrides
        let localPaths = [
            "Xproject.local.yml",
            "Xproject.local.yaml"
        ]

        for path in localPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                let localConfig = try loadConfiguration(from: url)
                configuration = try merge(base: configuration, override: localConfig)
                break
            }
        }

        // Apply environment variable overrides
        configuration = applyEnvironmentOverrides(to: configuration)

        // Final validation
        let configURL = URL(fileURLWithPath: configPath)
        try configuration.validate(baseDirectory: configURL.deletingLastPathComponent())

        return (configuration, configPath)
    }

    /// Load configuration from specific file with layered overrides
    public func loadConfigurationWithOverrides(from configPath: String) throws -> (XprojectConfiguration, String) {
        let url = URL(fileURLWithPath: configPath)

        // Check if file exists first
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigurationError.noConfigurationFound(searchPaths: [configPath])
        }

        var configuration = try loadConfiguration(from: url)

        // Try to load local overrides relative to the custom config
        let configDirectory = url.deletingLastPathComponent()
        let localPaths = [
            "Xproject.local.yml",
            "Xproject.local.yaml"
        ]

        for path in localPaths {
            let localURL = configDirectory.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: localURL.path) {
                let localConfig = try loadConfiguration(from: localURL)
                configuration = try merge(base: configuration, override: localConfig)
                break
            }
        }

        // Apply environment variable overrides
        configuration = applyEnvironmentOverrides(to: configuration)

        // Final validation
        try configuration.validate(baseDirectory: url.deletingLastPathComponent())

        return (configuration, configPath)
    }

    /// Merge two configurations, with override taking precedence
    private func merge(base: XprojectConfiguration, override: XprojectConfiguration) throws -> XprojectConfiguration {
        // For now, we'll do a simple override replacement
        // In the future, this could be more sophisticated (deep merging)
        return XprojectConfiguration(
            appName: override.appName.isEmpty ? base.appName : override.appName,
            workspacePath: override.workspacePath ?? base.workspacePath,
            projectPaths: base.projectPaths.merging(override.projectPaths) { _, new in new },
            setup: override.setup ?? base.setup,
            xcode: override.xcode ?? base.xcode,
            danger: override.danger ?? base.danger
        )
    }

    /// Apply environment variable overrides
    private func applyEnvironmentOverrides(to configuration: XprojectConfiguration) -> XprojectConfiguration {
        var config = configuration

        // Override with environment variables using XPROJECT_ prefix
        if let appName = ProcessInfo.processInfo.environment["XPROJECT_APP_NAME"] {
            config = XprojectConfiguration(
                appName: appName,
                workspacePath: config.workspacePath,
                projectPaths: config.projectPaths,
                setup: config.setup,
                xcode: config.xcode,
                danger: config.danger
            )
        }

        // Add more environment overrides as needed

        return config
    }
}

// MARK: - Configuration Errors

public enum ConfigurationError: Error, LocalizedError, Sendable {
    case noConfigurationFound(searchPaths: [String])
    case unsupportedFormat(extension: String, supportedExtensions: [String])
    case invalidFormat(format: String, file: String, underlyingError: Error)
    case validation(file: String, error: XprojectConfiguration.ValidationError)

    public var errorDescription: String? {
        switch self {
        case let .noConfigurationFound(paths):
            return "No configuration file found. Searched paths: \(paths.joined(separator: ", "))"
        case let .unsupportedFormat(ext, supported):
            return "Unsupported configuration format '.\(ext)'. Supported formats: \(supported.joined(separator: ", "))"
        case let .invalidFormat(format, file, error):
            return "Invalid \(format) format in \(file): \(error.localizedDescription)"
        case let .validation(file, error):
            return "Configuration validation failed in \(file): \(error.localizedDescription)"
        }
    }
}
