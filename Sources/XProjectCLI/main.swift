import ArgumentParser

struct XProjectCLI: ParsableCommand {
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
}

XProjectCLI.main()