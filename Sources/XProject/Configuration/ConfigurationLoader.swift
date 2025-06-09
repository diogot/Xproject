//
// ConfigurationLoader.swift
// XProject
//

import Foundation
import Yams

// MARK: - Configuration Format Protocol

public protocol ConfigurationFormat: Sendable {
    func load(from url: URL) throws -> XProjectConfiguration
    var supportedExtensions: [String] { get }
}

// MARK: - YAML Configuration Format

public struct YAMLConfigurationFormat: ConfigurationFormat {
    public let supportedExtensions = ["yml", "yaml"]

    public init() {}

    public func load(from url: URL) throws -> XProjectConfiguration {
        let data = try Data(contentsOf: url)
        let yamlString = String(data: data, encoding: .utf8) ?? ""

        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(XProjectConfiguration.self, from: yamlString)
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
    public func loadConfiguration() throws -> XProjectConfiguration {
        let possiblePaths = [
            "XProject.yml",
            "XProject.yaml",
            "rake-config.yml",    // Legacy compatibility
            "rake-config.yaml"    // Legacy compatibility
        ]

        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return try loadConfiguration(from: url)
            }
        }

        throw ConfigurationError.noConfigurationFound(searchPaths: possiblePaths)
    }

    /// Load configuration from specific file
    public func loadConfiguration(from url: URL) throws -> XProjectConfiguration {
        let fileExtension = url.pathExtension.lowercased()

        guard let format = formats.first(where: { $0.supportedExtensions.contains(fileExtension) }) else {
            throw ConfigurationError.unsupportedFormat(
                extension: fileExtension,
                supportedExtensions: formats.flatMap { $0.supportedExtensions }
            )
        }

        do {
            let configuration = try format.load(from: url)
            try configuration.validate()
            return configuration
        } catch let error as XProjectConfiguration.ValidationError {
            throw ConfigurationError.validation(file: url.path, error: error)
        } catch {
            throw error
        }
    }

    /// Load configuration with layered overrides
    public func loadConfigurationWithOverrides() throws -> XProjectConfiguration {
        var configuration = try loadConfiguration()

        // Try to load local overrides
        let localPaths = [
            "XProject.local.yml",
            "XProject.local.yaml"
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
        try configuration.validate()

        return configuration
    }

    /// Merge two configurations, with override taking precedence
    private func merge(base: XProjectConfiguration, override: XProjectConfiguration) throws -> XProjectConfiguration {
        // For now, we'll do a simple override replacement
        // In the future, this could be more sophisticated (deep merging)
        return XProjectConfiguration(
            appName: override.appName.isEmpty ? base.appName : override.appName,
            workspacePath: override.workspacePath ?? base.workspacePath,
            projectPaths: base.projectPaths.merging(override.projectPaths) { _, new in new },
            setup: override.setup ?? base.setup
        )
    }

    /// Apply environment variable overrides
    private func applyEnvironmentOverrides(to configuration: XProjectConfiguration) -> XProjectConfiguration {
        var config = configuration

        // Override with environment variables using XPROJECT_ prefix
        if let appName = ProcessInfo.processInfo.environment["XPROJECT_APP_NAME"] {
            config = XProjectConfiguration(
                appName: appName,
                workspacePath: config.workspacePath,
                projectPaths: config.projectPaths,
                setup: config.setup
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
    case validation(file: String, error: XProjectConfiguration.ValidationError)

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
