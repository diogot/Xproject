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
        let workingDirectory = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(workingDirectory: workingDirectory, customConfigPath: globalOptions.config)

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
        print("📋 Xproject Configuration")
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
                let isEnabled = brew.enabled ?? true
                print("   Brew: \(isEnabled ? "✅" : "❌")")
                if isEnabled, let formulas = brew.formulas {
                    print("     Formulas: \(formulas.joined(separator: ", "))")
                }
            }
        }
    }

    private func validateConfiguration(_ service: ConfigurationService) throws {
        print("✅ Validating configuration...")

        do {
            let config = try service.configuration

            // Explicitly validate configuration
            // Note: ConfigurationLoader already validates on load, but we call it here
            // to provide a clear validation point in the validate command
            let baseDirectory = URL(fileURLWithPath: globalOptions.resolvedWorkingDirectory)
            try config.validate(baseDirectory: baseDirectory)

            // Show the configuration file being used
            if let configPath = try? service.configurationFilePath {
                print("📄 Configuration file: \(configPath)")
            }

            print("✅ Configuration is valid!")

            // Additional checks
            var warnings: [String] = []

            // Check for missing optional configurations
            warnings.append(contentsOf: validateXcodeConfiguration(config: config))

            if !warnings.isEmpty {
                print("\n⚠️  Warnings:")
                for warning in warnings {
                    print("   \(warning)")
                }
            }
        } catch let error as ConfigurationError {
            print("❌ Configuration validation failed:")
            print()
            print(formatConfigurationError(error))
            print()
            throw ExitCode.failure
        } catch {
            print("❌ Configuration validation failed:")
            print("   \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    /// Formats a configuration error for display in the CLI with proper indentation and visual formatting.
    /// - Parameter error: The configuration error to format
    /// - Returns: A formatted string suitable for CLI output
    private func formatConfigurationError(_ error: ConfigurationError) -> String {
        let errorMessage = error.localizedDescription

        // Add some visual separation and formatting
        let lines = errorMessage.components(separatedBy: .newlines)
        var formattedLines: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                formattedLines.append("")
            } else if line.hasPrefix("   ") {
                // Already indented - keep it
                formattedLines.append(line)
            } else {
                // Add indentation for main error content
                formattedLines.append("   \(line)")
            }
        }

        return formattedLines.joined(separator: "\n")
    }

    private func validateXcodeConfiguration(config: XprojectConfiguration) -> [String] {
        var warnings: [String] = []

        guard let xcode = config.xcode else {
            warnings.append("No xcode configuration found. Add an 'xcode' section to use build/test commands")
            return warnings
        }

        // Validate test configuration
        if let testsConfig = xcode.tests {
            if testsConfig.schemes.isEmpty {
                warnings.append("Test configuration has no schemes defined")
            } else {
                for schemeConfig in testsConfig.schemes where schemeConfig.testDestinations.isEmpty {
                    warnings.append("Test scheme '\(schemeConfig.scheme)' has no test destinations")
                }
            }
        } else {
            warnings.append("No test configuration found. Add 'tests' section under 'xcode' to run tests")
        }

        // Validate release configuration
        if let release = xcode.release {
            for (envName, releaseConfig) in release {
                if releaseConfig.signing == nil {
                    warnings.append("Release environment '\(envName)' has no signing configuration. IPA export may fail.")
                } else if let signing = releaseConfig.signing {
                    let hasBasicSigning = signing.teamID != nil || signing.provisioningProfiles != nil
                    if !hasBasicSigning {
                        // swiftlint:disable:next line_length
                        warnings.append("Release environment '\(envName)' signing configuration may be incomplete (missing teamID or provisioningProfiles)")
                    }
                }
            }
        }

        return warnings
    }
}
