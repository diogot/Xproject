//
// CleanService.swift
// Xproject
//

import Foundation

/// Result of a clean operation
public struct CleanResult: Sendable {
    public let buildPath: String
    public let reportsPath: String
    public let buildRemoved: Bool
    public let reportsRemoved: Bool

    public var nothingToClean: Bool {
        !buildRemoved && !reportsRemoved
    }

    public init(buildPath: String, reportsPath: String, buildRemoved: Bool, reportsRemoved: Bool) {
        self.buildPath = buildPath
        self.reportsPath = reportsPath
        self.buildRemoved = buildRemoved
        self.reportsRemoved = reportsRemoved
    }
}

/// Error types for clean operations
public enum CleanError: Error, LocalizedError, Sendable {
    case removalFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .removalFailed(path, reason):
            return "Failed to remove '\(path)': \(reason)"
        }
    }
}

/// Protocol for file system operations to enable testing
public protocol FileSystemOperating: Sendable {
    func fileExists(atPath path: String) -> Bool
    func removeItem(atPath path: String) throws
}

/// Default implementation using FileManager
public struct DefaultFileSystemOperator: FileSystemOperating, Sendable {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func removeItem(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}

/// Service for cleaning build artifacts and test reports
public final class CleanService: Sendable {
    private let workingDirectory: String
    private let configurationProvider: any ConfigurationProviding
    private let fileSystem: any FileSystemOperating

    public init(
        workingDirectory: String,
        configurationProvider: any ConfigurationProviding,
        fileSystem: any FileSystemOperating = DefaultFileSystemOperator()
    ) {
        self.workingDirectory = workingDirectory
        self.configurationProvider = configurationProvider
        self.fileSystem = fileSystem
    }

    /// Clean build artifacts and test reports
    /// - Parameter dryRun: If true, don't actually remove anything
    /// - Returns: CleanResult describing what was (or would be) removed
    public func clean(dryRun: Bool = false) throws -> CleanResult {
        let config = try configurationProvider.configuration
        let buildPath = config.buildPath()
        let reportsPath = config.reportsPath()

        // Resolve to absolute paths
        let baseURL = URL(fileURLWithPath: workingDirectory)
        let absoluteBuildPath = baseURL.appendingPathComponent(buildPath).path
        let absoluteReportsPath = baseURL.appendingPathComponent(reportsPath).path

        // Check what exists
        let buildExists = fileSystem.fileExists(atPath: absoluteBuildPath)
        let reportsExists = fileSystem.fileExists(atPath: absoluteReportsPath)

        var buildRemoved = false
        var reportsRemoved = false

        if !dryRun {
            if buildExists {
                do {
                    try fileSystem.removeItem(atPath: absoluteBuildPath)
                    buildRemoved = true
                } catch {
                    throw CleanError.removalFailed(path: buildPath, reason: error.localizedDescription)
                }
            }

            if reportsExists {
                do {
                    try fileSystem.removeItem(atPath: absoluteReportsPath)
                    reportsRemoved = true
                } catch {
                    throw CleanError.removalFailed(path: reportsPath, reason: error.localizedDescription)
                }
            }
        } else {
            // In dry-run, report what would be removed
            buildRemoved = buildExists
            reportsRemoved = reportsExists
        }

        return CleanResult(
            buildPath: buildPath,
            reportsPath: reportsPath,
            buildRemoved: buildRemoved,
            reportsRemoved: reportsRemoved
        )
    }
}
