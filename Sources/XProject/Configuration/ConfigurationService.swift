import Foundation

// MARK: - Configuration Service

public final class ConfigurationService: @unchecked Sendable {
    public static let shared = ConfigurationService()
    
    private let lock = NSLock()
    private var _configuration: XProjectConfiguration?
    private let loader: ConfigurationLoader
    
    public init(loader: ConfigurationLoader = ConfigurationLoader()) {
        self.loader = loader
    }
    
    /// Get the current configuration, loading it if necessary
    public var configuration: XProjectConfiguration {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            
            if let config = _configuration {
                return config
            }
            
            let config = try loader.loadConfigurationWithOverrides()
            _configuration = config
            return config
        }
    }
    
    /// Reload configuration from disk
    public func reload() throws {
        lock.lock()
        defer { lock.unlock() }
        
        _configuration = try loader.loadConfigurationWithOverrides()
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
    
    /// Get configuration value by keypath
    func value(for keyPath: String) throws -> Any? {
        return try configuration.value(for: keyPath)
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
        guard let workspacePath = try workspacePath else { return nil }
        return resolvePath(workspacePath)
    }
    
    /// Get absolute path for project
    func projectURL(for target: String) throws -> URL? {
        guard let projectPath = try projectPath(for: target) else { return nil }
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