//
// main.swift
// Xproject
//

import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(
        name: [.short, .long],
        help: "Path to configuration file (default: auto-discover Xproject.yml, rake-config.yml)"
    )
    var config: String?

    @Option(
        name: [.customShort("C"), .long],
        help: "Working directory for the command (default: current directory)"
    )
    private var workingDirectory: String?

    @Flag(name: [.short, .long], help: "Show detailed output and commands being executed")
    var verbose = false

    /// Resolved working directory - uses provided value or current directory
    var resolvedWorkingDirectory: String {
        workingDirectory ?? FileManager.default.currentDirectoryPath
    }
}

@main
struct XprojectCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xp",
        abstract: "A modern Xcode project build automation tool",
        discussion: """
            Version: \(GeneratedVersion.version)
            Project: https://github.com/diogot/Xproject
            """,
        version: GeneratedVersion.version,
        subcommands: [
            SetupCommand.self,
            BuildCommand.self,
            TestCommand.self,
            ReleaseCommand.self,
            CleanCommand.self,
            ConfigCommand.self,
            EnvironmentCommand.self,
            VersionCommand.self,
            SecretsCommand.self,
            ProvisionCommand.self,
            PRReportCommand.self
        ]
    )

    @OptionGroup var globalOptions: GlobalOptions
}
