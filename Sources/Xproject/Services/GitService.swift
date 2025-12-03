//
// GitService.swift
// Xproject
//

import Foundation

public final class GitService: Sendable {
    private let executor: CommandExecuting
    private let workingDirectory: String

    public init(workingDirectory: String, executor: CommandExecuting) {
        self.workingDirectory = workingDirectory
        self.executor = executor
    }

    // MARK: - Repository Status

    /// Check if the git repository has uncommitted changes
    /// - Returns: True if repository is clean (no changes), false otherwise
    /// - Throws: GitServiceError if unable to check status
    public func isRepositoryClean() throws -> Bool {
        // Check for modified/deleted files
        let diffResult = try executor.executeReadOnly("git diff --quiet")
        if diffResult.exitCode != 0 {
            return false
        }

        // Check for untracked files
        let untrackedResult = try executor.executeReadOnly("git ls-files --other --exclude-standard")
        if !untrackedResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        return true
    }

    /// Get list of modified and untracked files
    /// - Returns: Array of file paths that have changes
    /// - Throws: GitServiceError if unable to get status
    public func getModifiedFiles() throws -> [String] {
        var files: [String] = []

        // Get modified/deleted files
        let diffResult = try executor.executeReadOnly("git diff --name-only")
        if diffResult.exitCode == 0 {
            let diffFiles = diffResult.output
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
            files.append(contentsOf: diffFiles)
        }

        // Get untracked files
        let untrackedResult = try executor.executeReadOnly("git ls-files --other --exclude-standard")
        if untrackedResult.exitCode == 0 {
            let untrackedFiles = untrackedResult.output
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
            files.append(contentsOf: untrackedFiles)
        }

        return files
    }

    /// Get expected version-related files for a project
    /// - Parameter projectPath: Path to the .xcodeproj file
    /// - Returns: Array of file paths expected to change during version bumps
    /// - Throws: GitServiceError if unable to find files
    public func getExpectedVersionFiles(projectPath: String) throws -> [String] {
        var files: [String] = []

        // Add project.pbxproj file
        let pbxprojPath = "\(projectPath)/project.pbxproj"
        files.append(pbxprojPath)

        // Find Info.plist files by parsing the project
        // For now, we'll use a simple approach - in production this would parse the pbxproj
        // to find INFOPLIST_FILE build settings
        let findInfoPlists = """
        find . -name "Info.plist" -not -path "*/build/*" -not -path "*/.build/*" -not -path "*/DerivedData/*"
        """
        let result = try executor.executeReadOnly(findInfoPlists)
        if result.exitCode == 0 {
            let plistFiles = result.output
                .split(separator: "\n")
                .map(String.init)
                .map { $0.replacingOccurrences(of: "./", with: "") }
                .filter { !$0.isEmpty }
            files.append(contentsOf: plistFiles)
        }

        return files
    }

    // MARK: - Commit Operations

    /// Commit version bump changes
    /// - Parameters:
    ///   - message: Commit message
    ///   - files: Files to commit (if empty, commits all changes)
    /// - Throws: GitServiceError if commit fails
    public func commit(message: String, files: [String] = []) throws {
        // Add files using arguments array to avoid shell escaping issues
        if files.isEmpty {
            _ = try executor.execute("git add -A")
        } else {
            for file in files {
                _ = try executor.executeWithArguments(command: "/usr/bin/git", arguments: ["add", file])
            }
        }

        // Commit with message using arguments array to avoid shell injection
        let result = try executor.executeWithArguments(command: "/usr/bin/git", arguments: ["commit", "-m", message])

        guard result.exitCode == 0 else {
            throw GitServiceError.commitFailed(output: result.error)
        }
    }

    /// Commit version bump with standard message format
    /// - Parameters:
    ///   - version: The new version
    ///   - build: The build number
    ///   - files: Expected files to commit
    /// - Throws: GitServiceError if commit fails or unexpected files changed
    public func commitVersionBump(version: Version, build: Int, files: [String]) throws {
        // Verify only expected files changed
        let modifiedFiles = try getModifiedFiles()
        let expectedSet = Set(files.map { $0.lowercased() })
        let modifiedSet = Set(modifiedFiles.map { $0.lowercased() })

        if !modifiedSet.isSubset(of: expectedSet) {
            let unexpected = modifiedSet.subtracting(expectedSet)
            throw GitServiceError.unexpectedChanges(
                expected: Array(expectedSet),
                found: Array(unexpected)
            )
        }

        // Commit with [skip ci] prefix
        let message = "[skip ci] Bumping build number to \(version.fullVersion(build: build))"
        try commit(message: message, files: files)
    }

    // MARK: - Tag Operations

    /// Check if a tag exists
    /// - Parameter tag: The tag name
    /// - Returns: True if tag exists
    /// - Throws: GitServiceError if unable to check
    public func tagExists(_ tag: String) throws -> Bool {
        let result = try executor.executeReadOnly("git tag -l '\(tag)'")
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Create a git tag
    /// - Parameter tag: The tag name
    /// - Throws: GitServiceError if tag creation fails or tag already exists
    public func createTag(_ tag: String) throws {
        // Check if tag already exists
        if try tagExists(tag) {
            throw GitServiceError.tagAlreadyExists(tag)
        }

        let result = try executor.execute("git tag '\(tag)'")
        guard result.exitCode == 0 else {
            throw GitServiceError.tagCreationFailed(tag: tag, output: result.error)
        }
    }

    /// Format a version tag using the provided format or default
    /// - Parameters:
    ///   - format: Custom tag format with placeholders: {target}, {env}, {version}, {build}
    ///   - target: The target name (e.g., "ios")
    ///   - environment: Optional environment name (e.g., "dev", "production")
    ///   - version: The version
    ///   - build: The build number
    /// - Returns: The formatted tag string
    public func formatTag(
        format: String?,
        target: String,
        environment: String?,
        version: Version,
        build: Int
    ) -> String {
        // Default format includes {env} prefix only if environment is provided
        let defaultFormat = environment != nil ? "{env}-{target}/{version}-{build}" : "{target}/{version}-{build}"
        var tag = format ?? defaultFormat

        tag = tag.replacingOccurrences(of: "{target}", with: target)
        tag = tag.replacingOccurrences(of: "{version}", with: version.description)
        tag = tag.replacingOccurrences(of: "{build}", with: String(build))

        if let env = environment {
            tag = tag.replacingOccurrences(of: "{env}", with: env)
        } else {
            // Remove {env} placeholder and any adjacent dash/hyphen if no env provided
            tag = tag.replacingOccurrences(of: "-{env}", with: "")
            tag = tag.replacingOccurrences(of: "{env}-", with: "")
            tag = tag.replacingOccurrences(of: "{env}", with: "")

            // Remove leading slash if present
            if tag.hasPrefix("/") {
                tag = String(tag.dropFirst())
            }
        }

        return tag
    }

    /// Create a version tag with standard or custom format
    /// - Parameters:
    ///   - version: The version
    ///   - build: The build number
    ///   - target: The target name (e.g., "ios")
    ///   - environment: Optional environment name (e.g., "production")
    ///   - tagFormat: Optional custom tag format with placeholders
    /// - Returns: The created tag name
    /// - Throws: GitServiceError if tag creation fails
    public func createVersionTag(
        version: Version,
        build: Int,
        target: String,
        environment: String? = nil,
        tagFormat: String? = nil
    ) throws -> String {
        let tag = formatTag(
            format: tagFormat,
            target: target,
            environment: environment,
            version: version,
            build: build
        )

        try createTag(tag)
        return tag
    }

    // MARK: - Push Operations

    /// Get current branch name
    /// - Returns: The current branch name
    /// - Throws: GitServiceError if unable to determine branch
    public func getCurrentBranch() throws -> String {
        let result = try executor.executeReadOnly("git rev-parse --abbrev-ref HEAD")
        guard result.exitCode == 0 else {
            throw GitServiceError.unableToGetBranch(output: result.error)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Push current branch and tags to remote
    /// - Parameter remote: The remote name (default: "origin")
    /// - Throws: GitServiceError if push fails
    public func pushWithTags(remote: String = "origin") throws {
        let branch = try getCurrentBranch()

        let result = try executor.execute("git push \(remote) \(branch) --tags")
        guard result.exitCode == 0 else {
            throw GitServiceError.pushFailed(output: result.error)
        }
    }
}

// MARK: - Git Service Errors

public enum GitServiceError: Error, LocalizedError, Sendable {
    case commitFailed(output: String)
    case tagCreationFailed(tag: String, output: String)
    case tagAlreadyExists(String)
    case pushFailed(output: String)
    case unableToGetBranch(output: String)
    case unexpectedChanges(expected: [String], found: [String])
    case repositoryDirty(files: [String])

    public var errorDescription: String? {
        switch self {
        case .commitFailed(let output):
            return """
            Git commit failed.

            Error: \(output)

            ✅ Make sure all changes are staged and there are no conflicts.
            """

        case let .tagCreationFailed(tag, output):
            return """
            Failed to create git tag '\(tag)'.

            Error: \(output)
            """

        case .tagAlreadyExists(let tag):
            return """
            Git tag '\(tag)' already exists.

            ✅ Use a different version or delete the existing tag first with: git tag -d \(tag)
            """

        case .pushFailed(let output):
            return """
            Git push failed.

            Error: \(output)

            ✅ Make sure you have push access to the remote repository.
            """

        case .unableToGetBranch(let output):
            return """
            Unable to determine current git branch.

            Error: \(output)

            ✅ Make sure you're in a git repository with a valid branch.
            """

        case let .unexpectedChanges(expected, found):
            return """
            Found unexpected uncommitted changes.

            Expected files: \(expected.joined(separator: ", "))
            But found changes in: \(found.joined(separator: ", "))

            ✅ Commit or stash unexpected changes before bumping version.
            """

        case .repositoryDirty(let files):
            return """
            Found unexpected uncommitted changes in the working directory.

            Found these changes:
            \(files.map { "  - \($0)" }.joined(separator: "\n"))

            ✅ Commit or stash your changes before creating a version tag.
            """
        }
    }
}
