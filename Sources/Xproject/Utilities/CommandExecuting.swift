//
// CommandExecuting.swift
// Xproject
//

import Foundation

// MARK: - Command Execution Protocol

public protocol CommandExecuting: Sendable {
    func execute(_ command: String, workingDirectory: URL?, environment: [String: String]?) throws -> CommandResult
    func executeOrThrow(_ command: String, workingDirectory: URL?, environment: [String: String]?) throws -> CommandResult
    func executeReadOnly(_ command: String, workingDirectory: URL?, environment: [String: String]?) throws -> CommandResult
    func executeWithStreamingOutput(_ command: String, workingDirectory: URL?, environment: [String: String]?) async throws -> CommandResult
    func commandExists(_ command: String) -> Bool
}

public extension CommandExecuting {
    func execute(_ command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> CommandResult {
        return try execute(command, workingDirectory: workingDirectory, environment: environment)
    }

    func executeOrThrow(_ command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> CommandResult {
        let result = try execute(command, workingDirectory: workingDirectory, environment: environment)

        if result.exitCode != 0 {
            throw CommandError.executionFailed(result: result)
        }

        return result
    }

    func executeReadOnly(_ command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> CommandResult {
        return try execute(command, workingDirectory: workingDirectory, environment: environment)
    }

    func executeWithStreamingOutput(
        _ command: String,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        return try await executeWithStreamingOutput(command, workingDirectory: workingDirectory, environment: environment)
    }
}
