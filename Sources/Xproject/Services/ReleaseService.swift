//
// ReleaseService.swift
// Xproject
//

import Foundation

// MARK: - Release Service Protocol

public protocol ReleaseServiceProtocol: Sendable {
    func createRelease(
        environment: String,
        archiveOnly: Bool,
        skipUpload: Bool,
        uploadOnly: Bool
    ) async throws -> ReleaseResults
}

// MARK: - Release Service

public final class ReleaseService: ReleaseServiceProtocol, Sendable {
    private let workingDirectory: String
    private let configurationProvider: any ConfigurationProviding
    private let xcodeClient: any XcodeClientProtocol

    public init(
        workingDirectory: String,
        configurationProvider: any ConfigurationProviding,
        xcodeClient: any XcodeClientProtocol
    ) {
        self.workingDirectory = workingDirectory
        self.configurationProvider = configurationProvider
        self.xcodeClient = xcodeClient
    }

    // MARK: - Public Methods

    public func createRelease(
        environment: String,
        archiveOnly: Bool = false,
        skipUpload: Bool = false,
        uploadOnly: Bool = false
    ) async throws -> ReleaseResults {
        let config = try configurationProvider.configuration
        let configFilePath = try configurationProvider.configurationFilePath

        guard let xcodeConfig = config.xcode else {
            throw ReleaseError.noXcodeConfiguration(configFile: configFilePath)
        }

        guard let releaseConfig = xcodeConfig.release?[environment] else {
            let availableEnvironments = xcodeConfig.release?.keys.sorted() ?? []
            throw ReleaseError.environmentNotFound(
                environment: environment,
                available: availableEnvironments
            )
        }

        var results = ReleaseResults(environment: environment, scheme: releaseConfig.scheme)

        // Upload-only mode: skip archive and IPA generation
        if uploadOnly {
            return try await performUpload(environment: environment, results: &results)
        }

        // Archive phase
        do {
            try await xcodeClient.archive(environment: environment)
            results.recordArchiveSuccess()
        } catch {
            results.recordArchiveFailure(error: error)
            return results
        }

        // If archive-only, we're done
        if archiveOnly {
            return results
        }

        // Generate IPA phase
        do {
            try await xcodeClient.generateIPA(environment: environment)
            results.recordIPASuccess()
        } catch {
            results.recordIPAFailure(error: error)
            return results
        }

        // Upload phase (unless skipped)
        if !skipUpload {
            return try await performUpload(environment: environment, results: &results)
        }

        return results
    }

    // MARK: - Private Methods

    private func performUpload(environment: String, results: inout ReleaseResults) async throws -> ReleaseResults {
        do {
            try await xcodeClient.upload(environment: environment)
            results.recordUploadSuccess()
        } catch {
            results.recordUploadFailure(error: error)
        }
        return results
    }
}

// MARK: - Release Results

public struct ReleaseResults: Sendable {
    public let environment: String
    public let scheme: String

    public private(set) var archiveSucceeded: Bool?
    public private(set) var archiveError: Error?

    public private(set) var ipaSucceeded: Bool?
    public private(set) var ipaError: Error?

    public private(set) var uploadSucceeded: Bool?
    public private(set) var uploadError: Error?

    public var hasFailures: Bool {
        return archiveSucceeded == false || ipaSucceeded == false || uploadSucceeded == false
    }

    public var isComplete: Bool {
        // Check if at least one operation was attempted
        let hasAttemptedAnything = archiveSucceeded != nil || ipaSucceeded != nil || uploadSucceeded != nil

        guard hasAttemptedAnything else {
            return false
        }

        // If we attempted archive, it must succeed
        if archiveSucceeded != nil && archiveSucceeded == false {
            return false
        }

        // If we attempted IPA generation, it must succeed
        if ipaSucceeded != nil && ipaSucceeded == false {
            return false
        }

        // If we attempted upload, it must succeed
        if uploadSucceeded != nil && uploadSucceeded == false {
            return false
        }

        return true
    }

    init(environment: String, scheme: String) {
        self.environment = environment
        self.scheme = scheme
    }

    mutating func recordArchiveSuccess() {
        archiveSucceeded = true
        archiveError = nil
    }

    mutating func recordArchiveFailure(error: Error) {
        archiveSucceeded = false
        archiveError = error
    }

    mutating func recordIPASuccess() {
        ipaSucceeded = true
        ipaError = nil
    }

    mutating func recordIPAFailure(error: Error) {
        ipaSucceeded = false
        ipaError = error
    }

    mutating func recordUploadSuccess() {
        uploadSucceeded = true
        uploadError = nil
    }

    mutating func recordUploadFailure(error: Error) {
        uploadSucceeded = false
        uploadError = error
    }
}

// MARK: - Release Errors

public enum ReleaseError: Error, LocalizedError, Sendable {
    case noReleaseConfiguration(configFile: String?)
    case noXcodeConfiguration(configFile: String?)
    case environmentNotFound(environment: String, available: [String])
    case archiveFailed(environment: String, error: Error)
    case ipaGenerationFailed(environment: String, error: Error)
    case uploadFailed(environment: String, error: Error)

    public var errorDescription: String? {
        switch self {
        case let .noReleaseConfiguration(configFile):
            let fileInfo = configFile.map { " (loaded from \($0))" } ?? ""
            return "No release configuration found in xcode.release\(fileInfo). Add a 'release' section under 'xcode' in your configuration file."
        case let .noXcodeConfiguration(configFile):
            let fileInfo = configFile.map { " (loaded from \($0))" } ?? ""
            return "No xcode configuration found\(fileInfo). Add an 'xcode' section to your configuration file."
        case let .environmentNotFound(environment, available):
            let availableList = available.isEmpty
                ? "No release environments configured."
                : "Available environments: \(available.joined(separator: ", "))"
            return "Release environment '\(environment)' not found in configuration. \(availableList)"
        case let .archiveFailed(environment, error):
            return "Archive failed for environment '\(environment)': \(error.localizedDescription)"
        case let .ipaGenerationFailed(environment, error):
            return "IPA generation failed for environment '\(environment)': \(error.localizedDescription)"
        case let .uploadFailed(environment, error):
            return "Upload failed for environment '\(environment)': \(error.localizedDescription)"
        }
    }
}
