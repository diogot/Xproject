import Foundation

// MARK: - Main Configuration

public struct XProjectConfiguration: Codable, Sendable {
    public let appName: String
    public let workspacePath: String?
    public let projectPaths: [String: String]
    public let setup: SetupConfiguration?
    
    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case workspacePath = "workspace_path"
        case projectPaths = "project_path"
        case setup
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

public extension XProjectConfiguration {
    /// Get project path for a specific target
    func projectPath(for target: String) -> String? {
        return projectPaths[target]
    }
    
    /// Check if a component is enabled
    func isEnabled(_ keyPath: String) -> Bool {
        // Parse keypath like "setup.brew" and check if enabled
        let components = keyPath.split(separator: ".")
        guard components.count >= 2 else { return false }
        
        switch (components[0], components[1]) {
        case ("setup", "brew"):
            return setup?.brew?.enabled ?? false
        default:
            return false
        }
    }
    
    /// Get configuration value by keypath (like original Config class)
    func value(for keyPath: String) -> Any? {
        let components = keyPath.split(separator: ".")
        
        switch components.count {
        case 1:
            switch components[0] {
            case "app_name": return appName
            case "workspace_path": return workspacePath
            default: return nil
            }
        default:
            return nil
        }
    }
}

// MARK: - Validation

public extension XProjectConfiguration {
    struct ValidationError: Error, LocalizedError, Sendable {
        let message: String
        
        public var errorDescription: String? {
            return message
        }
    }
    
    func validate() throws {
        if appName.isEmpty {
            throw ValidationError(message: "app_name cannot be empty")
        }
        
        if projectPaths.isEmpty {
            throw ValidationError(message: "at least one project_path must be specified")
        }
        
        // Validate project paths exist
        for (target, path) in projectPaths {
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw ValidationError(message: "project path for '\(target)' not found: \(path)")
            }
        }
        
        // Validate workspace path if specified
        if let workspacePath = workspacePath {
            let url = URL(fileURLWithPath: workspacePath)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw ValidationError(message: "workspace not found: \(workspacePath)")
            }
        }
    }
}