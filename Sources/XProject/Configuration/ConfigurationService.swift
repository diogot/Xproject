//
// ConfigurationService.swift
// XProject
//

import Foundation

// MARK: - Configuration Service Protocol

public protocol ConfigurationProviding: Sendable {
    var configuration: XProjectConfiguration { get throws }
    var configurationFilePath: String? { get throws }
}

// MARK: - Configuration Service

public final class ConfigurationService: ConfigurationProviding, @unchecked Sendable {
    public static let shared = ConfigurationService()

    private let lock = NSLock()
    private var _configuration: XProjectConfiguration?
    private var _configurationFilePath: String?
    private let loader: ConfigurationLoader
    private let customConfigPath: String?

    public init(loader: ConfigurationLoader = ConfigurationLoader(), customConfigPath: String? = nil) {
        self.loader = loader
        self.customConfigPath = customConfigPath
    }

    /// Get the current configuration, loading it if necessary
    public var configuration: XProjectConfiguration {
        get throws {
            lock.lock()
            defer { lock.unlock() }

            if let config = _configuration {
                return config
            }

            let (config, filePath) = try {
                if let customConfigPath = customConfigPath {
                    return try loader.loadConfigurationWithOverrides(from: customConfigPath)
                } else {
                    return try loader.loadConfigurationWithOverridesAndPath()
                }
            }()
            _configuration = config
            _configurationFilePath = filePath
            return config
        }
    }

    /// Reload configuration from disk
    public func reload() throws {
        lock.lock()
        defer { lock.unlock() }

        let (config, filePath) = try {
            if let customConfigPath = customConfigPath {
                return try loader.loadConfigurationWithOverrides(from: customConfigPath)
            } else {
                return try loader.loadConfigurationWithOverridesAndPath()
            }
        }()
        _configuration = config
        _configurationFilePath = filePath
    }

    /// Check if configuration is loaded
    public var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }

        return _configuration != nil
    }

    /// Clear cached configuration
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }

        _configuration = nil
        _configurationFilePath = nil
    }

    /// Get the path of the currently loaded configuration file
    public var configurationFilePath: String? {
        get throws {
            lock.lock()
            defer { lock.unlock() }

            if _configuration == nil {
                // Trigger loading to get the file path
                _ = try configuration
            }

            return _configurationFilePath
        }
    }
}

// MARK: - Convenience Extensions

public extension ConfigurationService {
    /// Get app name
    var appName: String {
        get throws {
            return try configuration.appName
        }
    }

    /// Get workspace path
    var workspacePath: String? {
        get throws {
            return try configuration.workspacePath
        }
    }

    /// Get project paths
    var projectPaths: [String: String] {
        get throws {
            return try configuration.projectPaths
        }
    }

    /// Get project path for specific target
    func projectPath(for target: String) throws -> String? {
        return try configuration.projectPath(for: target)
    }

    /// Check if a feature is enabled
    func isEnabled(_ keyPath: String) throws -> Bool {
        return try configuration.isEnabled(keyPath)
    }

    /// Get setup configuration
    var setup: SetupConfiguration? {
        get throws {
            return try configuration.setup
        }
    }
}

// MARK: - Path Utilities

public extension ConfigurationService {
    /// Resolve path relative to project root
    func resolvePath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        } else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }
    }

    /// Get absolute path for workspace
    func workspaceURL() throws -> URL? {
        guard let workspacePath = try workspacePath else {
            return nil
        }
        return resolvePath(workspacePath)
    }

    /// Get absolute path for project
    func projectURL(for target: String) throws -> URL? {
        guard let projectPath = try projectPath(for: target) else {
            return nil
        }
        return resolvePath(projectPath)
    }

    /// Get build artifacts path (default implementation)
    func buildPath() -> URL {
        return resolvePath("build")
    }

    /// Get test reports path (default implementation)
    func reportsPath() -> URL {
        return resolvePath("reports")
    }
}
