//
// EnvironmentCommand.swift
// Xproject
//

import ArgumentParser
import Foundation
import Xproject

struct EnvironmentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "env",
        abstract: "Manage environment configurations",
        discussion: """
        Environment management commands for loading and switching between different
        deployment environments (dev, staging, production, etc.).

        Common workflow:
          1. xp env list                    # See available environments
          2. xp env show dev                # Preview dev environment
          3. xp env load dev                # Load dev environment
          4. xp env current                 # Verify active environment
        """,
        subcommands: [
            EnvListCommand.self,
            EnvShowCommand.self,
            EnvCurrentCommand.self,
            EnvLoadCommand.self,
            EnvValidateCommand.self,
        ]
    )
}

// MARK: - List Command

struct EnvListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available environments"
    )

    @OptionGroup var globalOptions: GlobalOptions

    func run() async throws {
        let service = EnvironmentService()
        let workingDir = globalOptions.resolvedWorkingDirectory

        let environments = try service.listEnvironments(workingDirectory: workingDir)
        let current = try? service.getCurrentEnvironment(workingDirectory: workingDir)

        print("Available environments:")
        for env in environments.sorted() {
            let marker = env == current ? "* " : "  "
            print("\(marker)\(env)")
        }

        if let current = current {
            print("\nCurrent: \(current)")
        } else {
            print("\nNo environment loaded")
        }
    }
}

// MARK: - Show Command

struct EnvShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display environment variables"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name (defaults to current)")
    var name: String?

    func run() async throws {
        let service = EnvironmentService()
        let workingDir = globalOptions.resolvedWorkingDirectory

        // Get environment name
        let envName: String
        if let name = name {
            envName = name
        } else {
            guard let current = try service.getCurrentEnvironment(workingDirectory: workingDir) else {
                throw EnvironmentError.noCurrentEnvironment
            }
            envName = current
        }

        // Load variables
        let variables = try service.loadEnvironmentVariables(
            name: envName,
            workingDirectory: workingDir
        )

        // Pretty print
        print("Environment: \(envName)")
        print("Variables:")
        printYAML(variables, indent: 0)
    }

    private func printYAML(_ value: Any, indent: Int) {
        let prefix = String(repeating: "  ", count: indent)

        if let dict = value as? [String: Any] {
            for key in dict.keys.sorted() {
                if let nestedDict = dict[key] as? [String: Any] {
                    print("\(prefix)\(key):")
                    printYAML(nestedDict, indent: indent + 1)
                } else {
                    print("\(prefix)\(key): \(dict[key]!)")
                }
            }
        }
    }
}

// MARK: - Current Command

struct EnvCurrentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "current",
        abstract: "Show currently active environment"
    )

    @OptionGroup var globalOptions: GlobalOptions

    func run() async throws {
        let service = EnvironmentService()

        guard let current = try service.getCurrentEnvironment(
            workingDirectory: globalOptions.resolvedWorkingDirectory
        ) else {
            throw EnvironmentError.noCurrentEnvironment
        }

        print(current)
    }
}

// MARK: - Load Command

struct EnvLoadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "load",
        abstract: "Load an environment and generate xcconfig files"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name or index (1-based). If omitted, shows available environments.")
    var nameOrIndex: String?
    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun: Bool = false
    @Flag(name: .long, help: "Skip Swift code generation")
    var skipSwift: Bool = false

    func run() async throws {
        let service = EnvironmentService()
        let workingDir = globalOptions.resolvedWorkingDirectory

        // Determine environment name
        let name: String
        if let input = nameOrIndex {
            // Parse input as index or name
            name = try parseEnvironmentInput(input, service: service, workingDirectory: workingDir)
        } else {
            // Interactive selection
            name = try selectEnvironmentInteractively(service: service, workingDirectory: workingDir)
        }

        // Validate environment configuration
        try service.validateEnvironmentConfig(workingDirectory: workingDir)

        // Validate specific environment
        try service.validateEnvironmentVariables(name: name, workingDirectory: workingDir)

        // Load environment variables
        let variables = try service.loadEnvironmentVariables(
            name: name,
            workingDirectory: workingDir
        )

        // Generate xcconfigs
        try service.generateXCConfigs(
            environmentName: name,
            variables: variables,
            workingDirectory: workingDir,
            dryRun: dryRun
        )

        // Generate Swift files
        if !skipSwift {
            try service.generateSwiftFiles(
                environmentName: name,
                variables: variables,
                workingDirectory: workingDir,
                dryRun: dryRun
            )
        }

        // Set current environment
        if !dryRun {
            try service.setCurrentEnvironment(
                name: name,
                workingDirectory: workingDir
            )
        }

        let action = dryRun ? "Would load" : "Loaded"
        print("\(action) environment: \(name)")
    }

    private func parseEnvironmentInput(_ input: String, service: EnvironmentService, workingDirectory: String) throws -> String {
        // Check if input is a number (index)
        if let index = Int(input) {
            let environments = try service.listEnvironments(workingDirectory: workingDirectory).sorted()
            guard index >= 1 && index <= environments.count else {
                throw ValidationError("Invalid environment index: \(index). Valid range: 1-\(environments.count)")
            }
            return environments[index - 1]  // Convert 1-based to 0-based
        } else {
            // Treat as environment name
            return input
        }
    }

    private func selectEnvironmentInteractively(service: EnvironmentService, workingDirectory: String) throws -> String {
        let environments = try service.listEnvironments(workingDirectory: workingDirectory).sorted()

        guard !environments.isEmpty else {
            throw EnvironmentError.invalidEnvironmentDirectory
        }

        // Get current environment if any
        let current = try? service.getCurrentEnvironment(workingDirectory: workingDirectory)

        // Display numbered list
        print("Available environments:")
        for (index, env) in environments.enumerated() {
            let marker = env == current ? "* " : "  "
            print("\(marker)\(index + 1). \(env)")
        }
        print()

        // Prompt for input with current environment in brackets if available
        if let current = current {
            print("Enter environment number or name [\(current)]: ", terminator: "")
        } else {
            print("Enter environment number or name: ", terminator: "")
        }
        let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""

        // If empty input and there's a current environment, use it
        if input.isEmpty {
            if let current = current {
                print("Using current environment: \(current)")
                return current
            } else {
                throw ValidationError("No environment selected")
            }
        }

        // Parse input
        return try parseEnvironmentInput(input, service: service, workingDirectory: workingDirectory)
    }
}

// MARK: - Validate Command

struct EnvValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate environment configuration"
    )

    @OptionGroup var globalOptions: GlobalOptions

    func run() async throws {
        let service = EnvironmentService()
        let workingDir = globalOptions.resolvedWorkingDirectory

        // Validate config
        try service.validateEnvironmentConfig(workingDirectory: workingDir)
        print("✓ env/config.yml is valid")

        // Validate all environments
        let environments = try service.listEnvironments(workingDirectory: workingDir)
        for env in environments {
            try service.validateEnvironmentVariables(
                name: env,
                workingDirectory: workingDir
            )
            print("✓ env/\(env)/env.yml is valid")
        }

        print("\nAll environment configurations are valid")
    }
}
