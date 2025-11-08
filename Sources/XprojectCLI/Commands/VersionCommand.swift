//
// VersionCommand.swift
// XprojectCLI
//

import ArgumentParser
import Foundation
import Xproject

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Manage project versioning and git tagging",
        discussion: """
        Version management commands for bumping versions, creating git tags, and managing releases.

        Common workflow:
          1. xp version show                    # Check current version
          2. xp version bump patch              # Bump patch version (1.0.0 → 1.0.1)
          3. xp version commit                  # Commit version changes
          4. xp version tag                     # Create git tag
          5. xp version push                    # Push to remote with tags

        All commands support --dry-run to preview changes without executing.
        """,
        subcommands: [
            VersionShowCommand.self,
            VersionBumpCommand.self,
            VersionCommitCommand.self,
            VersionTagCommand.self,
            VersionPushCommand.self
        ]
    )
}

// MARK: - Show Command

struct VersionShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display current version and build number"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Target name (defaults to first in config)")
    var target: String?

    func run() async throws {
        let configService = ConfigurationService(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            customConfigPath: globalOptions.config
        )
        let config = try configService.configuration

        // Determine target
        let targetName = try target ?? {
            guard let first = config.projectPaths.keys.first else {
                throw VersionCommandError.noTargetsConfigured
            }
            return first
        }()

        guard let projectPath = config.projectPaths[targetName] else {
            throw VersionCommandError.targetNotFound(targetName)
        }

        // Get version and build
        let executor = CommandExecutor(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            dryRun: false,
            verbose: globalOptions.verbose
        )
        let versionService = VersionService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)
        let version = try versionService.getCurrentVersion(target: targetName, projectPath: projectPath)

        let buildOffset = config.version?.buildNumberOffset ?? 0
        let build = try versionService.getCurrentBuild(offset: buildOffset)

        // Display
        print("Target: \(targetName)")
        print("Version: \(version.description)")
        print("Build: \(build)")
        print("Full Version: \(version.fullVersion(build: build))")
    }
}

// MARK: - Bump Command

struct VersionBumpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bump",
        abstract: "Bump version number",
        subcommands: [
            BumpPatchCommand.self,
            BumpMinorCommand.self,
            BumpMajorCommand.self
        ]
    )
}

struct BumpPatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "patch",
        abstract: "Bump patch version (1.0.0 → 1.0.1)"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Target name (defaults to first in config)") var target: String?
    @Flag(name: .long, help: "Show what would be done without executing") var dryRun = false

    func run() async throws {
        try await bumpVersion(type: .patch, target: target, globalOptions: globalOptions, dryRun: dryRun)
    }
}

struct BumpMinorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "minor",
        abstract: "Bump minor version (1.0.0 → 1.1.0)"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Target name (defaults to first in config)") var target: String?
    @Flag(name: .long, help: "Show what would be done without executing") var dryRun = false

    func run() async throws {
        try await bumpVersion(type: .minor, target: target, globalOptions: globalOptions, dryRun: dryRun)
    }
}

struct BumpMajorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "major",
        abstract: "Bump major version (1.0.0 → 2.0.0)"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Target name (defaults to first in config)") var target: String?
    @Flag(name: .long, help: "Show what would be done without executing") var dryRun = false

    func run() async throws {
        try await bumpVersion(type: .major, target: target, globalOptions: globalOptions, dryRun: dryRun)
    }
}

// MARK: - Commit Command

struct VersionCommitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commit",
        abstract: "Commit version bump changes"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Target name (defaults to first in config)") var target: String?
    @Flag(name: .long, help: "Show what would be done without executing") var dryRun = false

    func run() async throws {
        let configService = ConfigurationService(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            customConfigPath: globalOptions.config
        )
        let config = try configService.configuration

        // Determine target
        let targetName = try target ?? {
            guard let first = config.projectPaths.keys.first else {
                throw VersionCommandError.noTargetsConfigured
            }
            return first
        }()

        guard let projectPath = config.projectPaths[targetName] else {
            throw VersionCommandError.targetNotFound(targetName)
        }

        // Get current version and build
        let executor = CommandExecutor(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            dryRun: dryRun,
            verbose: globalOptions.verbose
        )
        let versionService = VersionService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)
        let version = try versionService.getCurrentVersion(target: targetName, projectPath: projectPath)

        let buildOffset = config.version?.buildNumberOffset ?? 0
        let build = try versionService.getCurrentBuild(offset: buildOffset)

        // Get expected files
        let gitService = GitService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)
        let expectedFiles = try gitService.getExpectedVersionFiles(projectPath: projectPath)

        if dryRun {
            print("[DRY RUN] Would commit version bump: \(version.fullVersion(build: build))")
            print("Expected files:")
            for file in expectedFiles {
                print("  - \(file)")
            }
            return
        }

        // Commit
        try gitService.commitVersionBump(version: version, build: build, files: expectedFiles)
        print("✓ Committed version bump: \(version.fullVersion(build: build))")
    }
}

// MARK: - Tag Command

struct VersionTagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Create git tag for current version"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Target name (defaults to first in config)") var target: String?
    @Option(name: .long, help: "Environment name (e.g., production)") var environment: String?
    @Flag(name: .long, help: "Show what would be done without executing") var dryRun = false

    func run() async throws {
        let configService = ConfigurationService(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            customConfigPath: globalOptions.config
        )
        let config = try configService.configuration

        // Determine target
        let targetName = try target ?? {
            guard let first = config.projectPaths.keys.first else {
                throw VersionCommandError.noTargetsConfigured
            }
            return first
        }()

        guard let projectPath = config.projectPaths[targetName] else {
            throw VersionCommandError.targetNotFound(targetName)
        }

        // Get current version and build
        let executor = CommandExecutor(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            dryRun: dryRun,
            verbose: globalOptions.verbose
        )
        let versionService = VersionService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)
        let version = try versionService.getCurrentVersion(target: targetName, projectPath: projectPath)

        let buildOffset = config.version?.buildNumberOffset ?? 0
        let build = try versionService.getCurrentBuild(offset: buildOffset)

        // Create tag
        let gitService = GitService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)

        if dryRun {
            var tag = ""
            if let environment = environment {
                tag += "\(environment)-"
            }
            tag += "\(targetName)/"
            tag += version.fullVersion(build: build)
            print("[DRY RUN] Would create tag: \(tag)")
            return
        }

        let tag = try gitService.createVersionTag(
            version: version,
            build: build,
            target: targetName,
            environment: environment
        )
        print("✓ Created tag: \(tag)")
    }
}

// MARK: - Push Command

struct VersionPushCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Push current branch and tags to remote"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Option(name: .long, help: "Remote name") var remote = "origin"
    @Flag(name: .long, help: "Show what would be done without executing") var dryRun = false

    func run() async throws {
        let executor = CommandExecutor(
            workingDirectory: globalOptions.resolvedWorkingDirectory,
            dryRun: dryRun,
            verbose: globalOptions.verbose
        )
        let gitService = GitService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)
        let branch = try gitService.getCurrentBranch()

        if dryRun {
            print("[DRY RUN] Would push branch '\(branch)' with tags to '\(remote)'")
            return
        }

        try gitService.pushWithTags(remote: remote)
        print("✓ Pushed branch '\(branch)' with tags to '\(remote)'")
    }
}

// MARK: - Helper Functions

private func bumpVersion(
    type: Version.BumpType,
    target: String?,
    globalOptions: GlobalOptions,
    dryRun: Bool
) async throws {
    let configService = ConfigurationService(
        workingDirectory: globalOptions.resolvedWorkingDirectory,
        customConfigPath: globalOptions.config
    )
    let config = try configService.configuration

    // Determine target
    let targetName = try target ?? {
        guard let first = config.projectPaths.keys.first else {
            throw VersionCommandError.noTargetsConfigured
        }
        return first
    }()

    guard let projectPath = config.projectPaths[targetName] else {
        throw VersionCommandError.targetNotFound(targetName)
    }

    // Get current version
    let executor = CommandExecutor(
        workingDirectory: globalOptions.resolvedWorkingDirectory,
        dryRun: dryRun,
        verbose: globalOptions.verbose
    )
    let versionService = VersionService(workingDirectory: globalOptions.resolvedWorkingDirectory, executor: executor)
    let currentVersion = try versionService.getCurrentVersion(target: targetName, projectPath: projectPath)
    let newVersion = currentVersion.bumped(type)

    if dryRun {
        print("[DRY RUN] Would bump \(type.rawValue) version:")
        print("  Current: \(currentVersion.description)")
        print("  New:     \(newVersion.description)")
        return
    }

    // Bump version
    try versionService.setVersion(newVersion, target: targetName, projectPath: projectPath)
    print("✓ Bumped \(type.rawValue) version:")
    print("  \(currentVersion.description) → \(newVersion.description)")
}

// MARK: - Errors

enum VersionCommandError: Error, LocalizedError {
    case noTargetsConfigured
    case targetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noTargetsConfigured:
            return """
            No targets configured in project configuration.

            ✅ Add at least one project_path to your Xproject.yml:
            project_path:
              ios: MyApp.xcodeproj
            """

        case .targetNotFound(let target):
            return """
            Target '\(target)' not found in project configuration.

            ✅ Check available targets with: xp config show
            """
        }
    }
}
