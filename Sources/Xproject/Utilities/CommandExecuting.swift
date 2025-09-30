//
// CommandExecuting.swift
// Xproject
//

import Foundation

// MARK: - Command Execution Protocol

public protocol CommandExecuting: Sendable {
    func execute(_ command: String, environment: [String: String]?) throws -> CommandResult
    func executeOrThrow(_ command: String, environment: [String: String]?) throws -> CommandResult
    func executeReadOnly(_ command: String, environment: [String: String]?) throws -> CommandResult
    func executeWithStreamingOutput(_ command: String, environment: [String: String]?) async throws -> CommandResult
    func commandExists(_ command: String) -> Bool
}

public extension CommandExecuting {
    func execute(_ command: String) throws -> CommandResult {
        return try execute(command, environment: nil)
    }

    func executeOrThrow(_ command: String) throws -> CommandResult {
        let result = try execute(command, environment: nil)

        if result.exitCode != 0 {
            throw CommandError.executionFailed(result: result)
        }

        return result
    }

    func executeReadOnly(_ command: String) throws -> CommandResult {
        return try executeReadOnly(command, environment: nil)
    }

    func executeWithStreamingOutput(_ command: String) async throws -> CommandResult {
        return try await executeWithStreamingOutput(command, environment: nil)
    }
}
