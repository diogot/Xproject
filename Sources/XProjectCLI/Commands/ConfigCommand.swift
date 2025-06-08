import ArgumentParser
import XProject
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage project configuration"
    )
    
    @Argument(help: "Configuration action (show, validate, generate)")
    var action: String
    
    @Option(help: "Environment to configure")
    var environment: String?
    
    func run() throws {
        let configService = ConfigurationService.shared
        
        switch action {
        case "show":
            try showConfiguration(configService)
        case "validate":
            try validateConfiguration(configService)
        case "generate":
            print("⚙️ Generating configuration files...")
            // TODO: Implement generate functionality
        default:
            print("❌ Unknown action: \(action)")
            throw ExitCode.failure
        }
    }
    
    private func showConfiguration(_ service: ConfigurationService) throws {
        print("📋 XProject Configuration")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        let config = try service.configuration
        
        print("📱 App Name: \(config.appName)")
        
        if let workspacePath = config.workspacePath {
            print("📁 Workspace: \(workspacePath)")
        }
        
        print("🎯 Projects:")
        for (target, path) in config.projectPaths {
            print("   \(target): \(path)")
        }
        
        if let setup = config.setup {
            print("⚙️ Setup:")
            if let brew = setup.brew {
                print("   Brew: \(brew.enabled ? "✅" : "❌")")
                if brew.enabled, let formulas = brew.formulas {
                    print("     Formulas: \(formulas.joined(separator: ", "))")
                }
            }
        }
    }
    
    private func validateConfiguration(_ service: ConfigurationService) throws {
        print("✅ Validating configuration...")
        
        do {
            let config = try service.configuration
            try config.validate()
            print("✅ Configuration is valid!")
            
            // Additional checks
            var warnings: [String] = []
            
            // Check if workspace/projects exist
            if let workspacePath = config.workspacePath {
                let url = service.resolvePath(workspacePath)
                if !FileManager.default.fileExists(atPath: url.path) {
                    warnings.append("Workspace file not found: \(workspacePath)")
                }
            }
            
            for (target, path) in config.projectPaths {
                let url = service.resolvePath(path)
                if !FileManager.default.fileExists(atPath: url.path) {
                    warnings.append("Project file not found for \(target): \(path)")
                }
            }
            
            if !warnings.isEmpty {
                print("\n⚠️  Warnings:")
                for warning in warnings {
                    print("   \(warning)")
                }
            }
            
        } catch {
            print("❌ Configuration validation failed:")
            print("   \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}