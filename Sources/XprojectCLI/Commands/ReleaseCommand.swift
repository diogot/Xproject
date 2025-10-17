//
// ReleaseCommand.swift
// Xproject
//

import ArgumentParser
import Foundation
import Xproject

struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Create a release build",
        discussion: """
            Creates a release build for the specified environment. By default, performs
            the full workflow: archive → generate IPA → upload to App Store Connect.

            You can control which steps to perform using the available flags:
            - --archive-only: Only create the archive
            - --skip-upload: Create archive and IPA, but don't upload
            - --upload-only: Only upload (assumes archive and IPA already exist)

            Examples:
              xp release production-ios              # Full release workflow
              xp release dev-ios --archive-only      # Only archive
              xp release staging-ios --skip-upload   # Archive + IPA, no upload
              xp release production-ios --upload-only # Upload existing build
            """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Release environment (e.g., production-ios, staging-tvos)")
    var environment: String

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun = false

    @Flag(name: .long, help: "Only create the archive (skip IPA generation and upload)")
    var archiveOnly = false

    @Flag(name: .long, help: "Skip uploading to App Store Connect")
    var skipUpload = false

    @Flag(name: .long, help: "Only upload to App Store Connect (assumes archive and IPA exist)")
    var uploadOnly = false

    func run() async throws {
        let workingDirectory = globalOptions.resolvedWorkingDirectory

        // Validate flags
        try validateFlags()

        // Print info block at start
        OutputFormatter.printInfoBlock(
            workingDirectory: workingDirectory,
            configFile: globalOptions.config,
            verbose: globalOptions.verbose
        )

        let configService = ConfigurationService(workingDirectory: workingDirectory, customConfigPath: globalOptions.config)
        let releaseService = ReleaseService(
            workingDirectory: workingDirectory,
            configurationProvider: configService,
            xcodeClient: XcodeClient(
                workingDirectory: workingDirectory,
                configurationProvider: configService,
                commandExecutor: CommandExecutor(workingDirectory: workingDirectory, dryRun: dryRun, verbose: globalOptions.verbose),
                verbose: globalOptions.verbose
            )
        )

        do {
            try await performRelease(releaseService: releaseService)
        } catch {
            print("❌ Release failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func validateFlags() throws {
        let flagCount = [archiveOnly, uploadOnly].filter { $0 }.count
        if flagCount > 1 {
            throw ValidationError("Cannot use --archive-only and --upload-only together")
        }

        if uploadOnly && skipUpload {
            throw ValidationError("Cannot use --upload-only and --skip-upload together")
        }
    }

    private func performRelease(releaseService: ReleaseService) async throws {
        print("🚀 Creating release for environment: \(environment)")
        printReleaseConfiguration()

        let results = try await releaseService.createRelease(
            environment: environment,
            archiveOnly: archiveOnly,
            skipUpload: skipUpload,
            uploadOnly: uploadOnly
        )

        printResults(results)

        if results.hasFailures {
            throw ExitCode.failure
        }
    }

    private func printReleaseConfiguration() {
        if uploadOnly {
            print("📤 Upload only mode")
        } else if archiveOnly {
            print("📦 Archive only mode")
        } else if skipUpload {
            print("📦 Archive + IPA mode (skipping upload)")
        } else {
            print("📦 Full release workflow (archive → IPA → upload)")
        }
    }

    private func printResults(_ results: ReleaseResults) {
        print("\n📋 Release Results for \(results.scheme)")
        print("   Environment: \(results.environment)")

        // Archive results
        if let archiveSucceeded = results.archiveSucceeded {
            if archiveSucceeded {
                print("   ✅ Archive succeeded")
            } else {
                print("   ❌ Archive failed")
                if let error = results.archiveError {
                    print("      \(error.localizedDescription)")
                }
            }
        }

        // IPA results
        if let ipaSucceeded = results.ipaSucceeded {
            if ipaSucceeded {
                print("   ✅ IPA generation succeeded")
            } else {
                print("   ❌ IPA generation failed")
                if let error = results.ipaError {
                    print("      \(error.localizedDescription)")
                }
            }
        }

        // Upload results
        if let uploadSucceeded = results.uploadSucceeded {
            if uploadSucceeded {
                print("   ✅ Upload succeeded")
            } else {
                print("   ❌ Upload failed")
                if let error = results.uploadError {
                    print("      \(error.localizedDescription)")
                }
            }
        }

        // Summary
        print("")
        if results.isComplete {
            print("✅ Release completed successfully!")
        } else {
            print("❌ Release failed")
        }
    }
}

struct ValidationError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        return message
    }
}
