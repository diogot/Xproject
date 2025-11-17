//
// VersionService.swift
// Xproject
//

import Foundation

public final class VersionService: Sendable {
    private let executor: CommandExecuting
    private let workingDirectory: String

    public init(workingDirectory: String, executor: CommandExecuting) {
        self.workingDirectory = workingDirectory
        self.executor = executor
    }

    // MARK: - Private Helpers

    /// Get the directory containing the .xcodeproj file
    /// - Parameter projectPath: Relative path to .xcodeproj (e.g., "App.xcodeproj" or "TV/TV.xcodeproj")
    /// - Returns: Directory path (workingDirectory or workingDirectory/subdirectory)
    private func getProjectDirectory(from projectPath: String) -> String {
        let projectDir = (projectPath as NSString).deletingLastPathComponent
        if projectDir.isEmpty {
            return workingDirectory
        }
        return (workingDirectory as NSString).appendingPathComponent(projectDir)
    }

    /// Validate that the project exists at the specified path
    /// - Parameter projectPath: Relative path to .xcodeproj
    /// - Throws: VersionServiceError.projectNotFound if project doesn't exist
    private func validateProjectExists(at projectPath: String) throws {
        let fullPath = (workingDirectory as NSString).appendingPathComponent(projectPath)
        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw VersionServiceError.projectNotFound(projectPath)
        }
    }

    /// Create a CommandExecutor for the project directory
    /// - Parameter projectPath: Relative path to .xcodeproj
    /// - Returns: CommandExecutor configured for the project's directory
    /// - Throws: VersionServiceError.projectNotFound if project doesn't exist
    private func createProjectExecutor(for projectPath: String) throws -> CommandExecuting {
        try validateProjectExists(at: projectPath)
        let projectDir = getProjectDirectory(from: projectPath)
        return executor.withWorkingDirectory(projectDir)
    }

    // MARK: - Version Reading

    /// Get the current marketing version from the project
    /// - Parameters:
    ///   - target: The target name (e.g., "ios") - used for context in error messages
    ///   - projectPath: Relative path to .xcodeproj (e.g., "App.xcodeproj" or "TV/TV.xcodeproj")
    /// - Returns: The current version
    /// - Throws: VersionServiceError if unable to read version
    /// - Note: agvtool must run in the directory containing the .xcodeproj file
    public func getCurrentVersion(target: String, projectPath: String) throws -> Version {
        let projectExecutor = try createProjectExecutor(for: projectPath)
        let command = "agvtool mvers -terse1"
        let result = try projectExecutor.executeReadOnly(command)

        guard result.exitCode == 0 else {
            throw VersionServiceError.agvtoolFailed(command: command, output: result.error)
        }

        let versionString = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try Version(string: versionString)
        } catch {
            throw VersionServiceError.invalidVersionFormat(versionString)
        }
    }

    /// Set the marketing version in the project
    /// - Parameters:
    ///   - version: The new version to set
    ///   - target: The target name (e.g., "ios") - used for context in error messages
    ///   - projectPath: Relative path to .xcodeproj (e.g., "App.xcodeproj" or "TV/TV.xcodeproj")
    /// - Throws: VersionServiceError if unable to set version
    /// - Note: agvtool must run in the directory containing the .xcodeproj file
    public func setVersion(_ version: Version, target: String, projectPath: String) throws {
        let projectExecutor = try createProjectExecutor(for: projectPath)
        let command = "agvtool new-marketing-version \(version.description)"
        let result = try projectExecutor.execute(command)

        guard result.exitCode == 0 else {
            throw VersionServiceError.agvtoolFailed(command: command, output: result.error)
        }
    }

    // MARK: - Build Number

    /// Calculate the current build number from git commit count + offset
    /// - Parameter offset: The build number offset
    /// - Returns: The calculated build number
    /// - Throws: VersionServiceError if unable to calculate build number
    public func getCurrentBuild(offset: Int) throws -> Int {
        let command = "git rev-list HEAD --count"
        let result = try executor.executeReadOnly(command)

        guard result.exitCode == 0 else {
            throw VersionServiceError.gitFailed(command: command, output: result.error)
        }

        guard let commitCount = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw VersionServiceError.invalidBuildNumber(result.output)
        }

        return commitCount + offset
    }

    // MARK: - Version Bumping

    /// Bump the version and update the project
    /// - Parameters:
    ///   - type: The bump type (patch, minor, or major)
    ///   - target: The target name (e.g., "ios")
    ///   - projectPath: Path to the .xcodeproj file
    /// - Returns: The new version after bumping
    /// - Throws: VersionServiceError if unable to bump version
    public func bumpVersion(_ type: Version.BumpType, target: String, projectPath: String) throws -> Version {
        let currentVersion = try getCurrentVersion(target: target, projectPath: projectPath)
        let newVersion = currentVersion.bumped(type)
        try setVersion(newVersion, target: target, projectPath: projectPath)
        return newVersion
    }

    // MARK: - Validation

    /// Check if agvtool is available
    /// - Throws: VersionServiceError.agvtoolNotFound if agvtool is not in PATH
    public func validateAgvtool() throws {
        let command = "which agvtool"
        let result = try executor.executeReadOnly(command)

        guard result.exitCode == 0 else {
            throw VersionServiceError.agvtoolNotFound
        }
    }

    /// Check if we're in a git repository
    /// - Throws: VersionServiceError.notGitRepository if not in a git repo
    public func validateGitRepository() throws {
        let command = "git rev-parse --git-dir"
        let result = try executor.executeReadOnly(command)

        guard result.exitCode == 0 else {
            throw VersionServiceError.notGitRepository
        }
    }
}

// MARK: - Version Service Errors

public enum VersionServiceError: Error, LocalizedError, Sendable {
    case agvtoolNotFound
    case notGitRepository
    case projectNotFound(String)
    case agvtoolFailed(command: String, output: String)
    case gitFailed(command: String, output: String)
    case invalidVersionFormat(String)
    case invalidBuildNumber(String)

    public var errorDescription: String? {
        switch self {
        case .agvtoolNotFound:
            return """
            agvtool not found in PATH.

            agvtool is part of Xcode Command Line Tools.
            ✅ Install with: xcode-select --install
            """

        case .notGitRepository:
            return """
            Not a git repository.

            Version management requires a git repository for build number calculation.
            ✅ Initialize with: git init
            """

        case .projectNotFound(let projectPath):
            return """
            Project not found at path: \(projectPath)

            ✅ Check your Xproject.yml configuration:
            project_path:
              ios: YourApp.xcodeproj
              tvos: TV/TV.xcodeproj
            """

        case let .agvtoolFailed(command, output):
            return """
            agvtool command failed: \(command)

            Error: \(output)

            ✅ Make sure you're in the project directory and the project has a valid Info.plist
            """

        case let .gitFailed(command, output):
            return """
            git command failed: \(command)

            Error: \(output)
            """

        case .invalidVersionFormat(let version):
            return """
            Invalid version format: '\(version)'

            ✅ Expected format: major.minor.patch or major.minor
            Examples: 1.2.3, 1.0
            """

        case .invalidBuildNumber(let value):
            return """
            Invalid build number: '\(value)'

            ✅ Build number must be a valid integer
            """
        }
    }
}
