//
// SetupCommand.swift
// XProject
//

import ArgumentParser
import Foundation
import XProject

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Setup project dependencies and environment"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun = false

    func run() async throws {
        if dryRun {
            print("🔧 Setting up project... (dry run)")
        } else {
            print("🔧 Setting up project...")
        }

        let configService = ConfigurationService(customConfigPath: globalOptions.config)
        let setupService = SetupService(configService: configService, dryRun: dryRun)

        do {
            try setupService.runSetup()
            if dryRun {
                print("✅ Setup completed! (dry run)")
            } else {
                print("✅ Setup completed!")
            }
        } catch let error as SetupError {
            switch error {
            case .brewNotInstalled:
                print("❌ \(error.localizedDescription)")
            case .brewFormulaFailed(let formula, _):
                print("❌ Failed to install \(formula): \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
    }
}
