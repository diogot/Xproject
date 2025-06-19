//
// main.swift
// Xproject
//

import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(
        name: [.short, .long],
        help: "Path to configuration file (default: auto-discover Xproject.yml, rake-config.yml)"
    )
    var config: String?
}

@main
struct XprojectCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xp",
        abstract: "A modern Xcode project build automation tool",
        version: "0.1.0",
        subcommands: [
            SetupCommand.self,
            BuildCommand.self,
            TestCommand.self,
            ReleaseCommand.self,
            ConfigCommand.self
        ]
    )

    @OptionGroup var globalOptions: GlobalOptions
}
