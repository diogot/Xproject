//
// CleanCommand.swift
// Xproject
//

import ArgumentParser
import Foundation
import Xproject

struct CleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove build artifacts and test reports"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Flag(name: .long, help: "Show what would be removed without deleting")
    var dryRun = false

    func run() async throws {
        let workingDirectory = globalOptions.resolvedWorkingDirectory

        // Print info block at start
        OutputFormatter.printInfoBlock(
            workingDirectory: workingDirectory,
            configFile: globalOptions.config,
            verbose: globalOptions.verbose
        )

        let modeDescription = dryRun ? " (dry run)" : ""
        print("🧹 Cleaning build artifacts\(modeDescription)...")

        let configService = ConfigurationService(
            workingDirectory: workingDirectory,
            customConfigPath: globalOptions.config
        )

        let cleanService = CleanService(
            workingDirectory: workingDirectory,
            configurationProvider: configService
        )

        do {
            let result = try cleanService.clean(dryRun: dryRun)

            if result.nothingToClean {
                print("Nothing to clean - directories do not exist:")
                print("  • \(result.buildPath)")
                print("  • \(result.reportsPath)")
                return
            }

            // Show what was removed
            print("Removing:")
            if result.buildRemoved {
                print("  • \(result.buildPath)")
            }
            if result.reportsRemoved {
                print("  • \(result.reportsPath)")
            }

            if dryRun {
                print("✅ Would clean the above directories (dry run)")
            } else {
                print("✅ Clean completed successfully!")
            }
        } catch {
            print("❌ Clean failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
