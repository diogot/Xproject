//
// SetupCommand.swift
// Xproject
//

import ArgumentParser
import Foundation
import Xproject

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Setup project dependencies and environment"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun = false

    func run() async throws {
        let modeDescription = dryRun ? " (dry run)" : ""
        print("🔧 Setting up project\(modeDescription)...")

        let configService = ConfigurationService(customConfigPath: globalOptions.config)
        let setupService = SetupService(configService: configService, dryRun: dryRun)

        do {
            try setupService.runSetup()
            print("✅ Setup completed successfully\(modeDescription)!")
        } catch let error as SetupError {
            switch error {
            case .brewNotInstalled:
                print("❌ Setup failed: \(error.localizedDescription)")
            case .brewFormulaFailed(let formula, _):
                print("❌ Setup failed while processing \(formula): \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
    }
}
