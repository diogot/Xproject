//
// ProvisionCommand.swift
// Xproject
//
// Commands for managing encrypted provisioning profiles
//

import ArgumentParser
import Foundation
import Xproject

struct ProvisionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provision",
        abstract: "Manage encrypted provisioning profiles",
        discussion: """
        Provisioning profile management commands for encrypting, decrypting, and
        installing provisioning profiles for CI/CD with manual signing workflows.

        Profiles are encrypted using AES-256-CBC with PBKDF2 key derivation via
        the system's /usr/bin/openssl. The encrypted archive can be safely stored
        in version control.

        Common workflow:
          1. xp provision encrypt           # Encrypt profiles
          2. xp provision decrypt           # Decrypt for installation
          3. xp provision install           # Install to system
          4. xp provision cleanup           # Remove decrypted files
        """,
        subcommands: [
            ProvisionEncryptCommand.self,
            ProvisionDecryptCommand.self,
            ProvisionListCommand.self,
            ProvisionInstallCommand.self,
            ProvisionCleanupCommand.self
        ]
    )
}

// MARK: - Encrypt Command

struct ProvisionEncryptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encrypt",
        abstract: "Encrypt provisioning profiles into an archive"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Option(name: .long, help: "Source directory containing .mobileprovision files")
    var source: String?
    @Flag(name: .long, help: "Show what would be encrypted without modifying files")
    var dryRun = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        let config = try configService.configuration
        guard let provisionConfig = config.provision else {
            throw ProvisionError.provisionNotEnabled
        }

        let provisionService = ProvisionService(
            workingDirectory: workingDir,
            appName: config.appName,
            fileManager: .default,
            dryRun: dryRun,
            verbose: globalOptions.verbose,
            interactiveEnabled: true
        )

        let sourcePath = source ?? provisionConfig.resolvedSourcePath
        let archivePath = provisionConfig.resolvedArchivePath

        if dryRun {
            let resolvedSource = resolvePath(sourcePath, workingDir: workingDir)
            let profiles = try FileManager.default.contentsOfDirectory(atPath: resolvedSource)
                .filter { $0.hasSuffix(".mobileprovision") }
                .sorted()

            print("Would encrypt \(profiles.count) profile(s) from: \(sourcePath)")
            print("Would create archive at: \(archivePath)")
            print("\nProfiles:")
            for profile in profiles {
                print("  - \(profile)")
            }
        } else {
            let result = try provisionService.encryptProfiles(
                sourcePath: sourcePath,
                archivePath: archivePath
            )

            print("✓ Encrypted \(result.profileCount) profile(s)")
            print("  Archive: \(result.archivePath)")
            print("  Size: \(formatBytes(result.archiveSize))")
            print("\nProfiles:")
            for profile in result.profileNames {
                print("  - \(profile)")
            }
        }
    }

    private func resolvePath(_ path: String, workingDir: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDir as NSString).appendingPathComponent(path)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Decrypt Command

struct ProvisionDecryptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decrypt",
        abstract: "Decrypt provisioning profile archive"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Flag(name: .long, help: "Show what would be decrypted without extracting files")
    var dryRun = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        let config = try configService.configuration
        guard let provisionConfig = config.provision else {
            throw ProvisionError.provisionNotEnabled
        }

        let provisionService = ProvisionService(
            workingDirectory: workingDir,
            appName: config.appName,
            fileManager: .default,
            dryRun: dryRun,
            verbose: globalOptions.verbose,
            interactiveEnabled: true
        )

        let archivePath = provisionConfig.resolvedArchivePath
        let extractPath = provisionConfig.resolvedExtractPath

        if dryRun {
            // List profiles to show what would be extracted
            let profiles = try provisionService.listProfiles(archivePath: archivePath)
            print("Would decrypt archive: \(archivePath)")
            print("Would extract to: \(extractPath)")
            print("\nProfiles (\(profiles.count)):")
            for profile in profiles {
                print("  - \(profile)")
            }
        } else {
            let result = try provisionService.decryptProfiles(
                archivePath: archivePath,
                extractPath: extractPath
            )

            print("✓ Decrypted \(result.profileCount) profile(s)")
            print("  Extracted to: \(result.extractPath)")
            print("\nProfiles:")
            for profile in result.profileNames {
                print("  - \(profile)")
            }
        }
    }
}

// MARK: - List Command

struct ProvisionListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List profiles in encrypted archive"
    )

    @OptionGroup var globalOptions: GlobalOptions

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        let config = try configService.configuration
        guard let provisionConfig = config.provision else {
            throw ProvisionError.provisionNotEnabled
        }

        let provisionService = ProvisionService(
            workingDirectory: workingDir,
            appName: config.appName,
            fileManager: .default,
            dryRun: false,
            verbose: globalOptions.verbose,
            interactiveEnabled: true
        )

        let archivePath = provisionConfig.resolvedArchivePath
        let profiles = try provisionService.listProfiles(archivePath: archivePath)

        print("Profiles in \(archivePath):")
        print("")
        if profiles.isEmpty {
            print("  (no profiles found)")
        } else {
            for profile in profiles {
                print("  - \(profile)")
            }
            print("")
            print("Total: \(profiles.count) profile(s)")
        }
    }
}

// MARK: - Install Command

struct ProvisionInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install decrypted profiles to system"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Flag(name: .long, help: "Show what would be installed without copying files")
    var dryRun = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        let config = try configService.configuration
        guard let provisionConfig = config.provision else {
            throw ProvisionError.provisionNotEnabled
        }

        let provisionService = ProvisionService(
            workingDirectory: workingDir,
            appName: config.appName,
            fileManager: .default,
            dryRun: dryRun,
            verbose: globalOptions.verbose,
            interactiveEnabled: true
        )

        let extractPath = provisionConfig.resolvedExtractPath
        let systemPath = NSString(string: "~/Library/MobileDevice/Provisioning Profiles").expandingTildeInPath

        if dryRun {
            let resolvedExtract = resolvePath(extractPath, workingDir: workingDir)
            let profiles = try FileManager.default.contentsOfDirectory(atPath: resolvedExtract)
                .filter { $0.hasSuffix(".mobileprovision") }
                .sorted()

            print("Would install \(profiles.count) profile(s)")
            print("From: \(extractPath)")
            print("To: \(systemPath)")
            print("\nProfiles:")
            for profile in profiles {
                print("  - \(profile)")
            }
        } else {
            let result = try provisionService.installProfiles(extractPath: extractPath)

            print("✓ Installation complete")
            print("  Installed: \(result.installedCount)")
            print("  Skipped: \(result.skippedCount) (already installed)")

            if !result.installedProfiles.isEmpty {
                print("\nInstalled profiles:")
                for profile in result.installedProfiles {
                    print("  ✓ \(profile)")
                }
            }

            if !result.skippedProfiles.isEmpty {
                print("\nSkipped profiles (identical):")
                for profile in result.skippedProfiles {
                    print("  - \(profile)")
                }
            }
        }
    }

    private func resolvePath(_ path: String, workingDir: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDir as NSString).appendingPathComponent(path)
    }
}

// MARK: - Cleanup Command

struct ProvisionCleanupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Remove decrypted profiles and staging files"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Flag(name: .long, help: "Show what would be removed without deleting files")
    var dryRun = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        let config = try configService.configuration
        guard let provisionConfig = config.provision else {
            throw ProvisionError.provisionNotEnabled
        }

        let extractPath = provisionConfig.resolvedExtractPath
        let stagingPath = "tmp/provision"

        if dryRun {
            var wouldRemove: [String] = []
            let resolvedExtract = resolvePath(extractPath, workingDir: workingDir)
            let resolvedStaging = resolvePath(stagingPath, workingDir: workingDir)

            if FileManager.default.fileExists(atPath: resolvedExtract) {
                wouldRemove.append(extractPath)
            }
            if FileManager.default.fileExists(atPath: resolvedStaging) {
                wouldRemove.append(stagingPath)
            }

            if wouldRemove.isEmpty {
                print("No files to clean up")
            } else {
                print("Would remove \(wouldRemove.count) path(s):")
                for path in wouldRemove {
                    print("  - \(path)")
                }
            }
        } else {
            let provisionService = ProvisionService(
                workingDirectory: workingDir,
                appName: config.appName,
                fileManager: .default,
                dryRun: false,
                verbose: globalOptions.verbose,
                interactiveEnabled: true
            )

            let result = try provisionService.cleanup(extractPath: extractPath)

            if result.removedCount == 0 {
                print("No files to clean up")
            } else {
                print("✓ Cleaned up \(result.removedCount) path(s)")
                for path in result.removedPaths {
                    print("  - \(path)")
                }
            }
        }
    }

    private func resolvePath(_ path: String, workingDir: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDir as NSString).appendingPathComponent(path)
    }
}
