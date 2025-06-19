//
// ConfigCommand.swift
// Xproject
//

import ArgumentParser
import Foundation
import Xproject

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage project configuration"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Configuration action (show, validate, generate)")
    var action: String

    @Option(help: "Environment to configure")
    var environment: String?

    func run() async throws {
        let configService = ConfigurationService(customConfigPath: globalOptions.config)

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

            // Check for missing optional configurations
            warnings.append(contentsOf: validateXcodeConfiguration(config: config))

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

    private func validateXcodeConfiguration(config: XprojectConfiguration) -> [String] {
        var warnings: [String] = []

        guard let xcode = config.xcode else {
            warnings.append("No xcode configuration found. Add an 'xcode' section to use build/test commands")
            return warnings
        }

        guard let testsConfig = xcode.tests else {
            warnings.append("No test configuration found. Add 'tests' section under 'xcode' to run tests")
            return warnings
        }

        if testsConfig.schemes.isEmpty {
            warnings.append("Test configuration has no schemes defined")
        } else {
            for schemeConfig in testsConfig.schemes where schemeConfig.testDestinations.isEmpty {
                warnings.append("Test scheme '\(schemeConfig.scheme)' has no test destinations")
            }
        }

        return warnings
    }
}
