//
// CommandError.swift
// Xproject
//

import Foundation

public enum CommandError: Error, LocalizedError, Sendable {
    case executionFailed(result: CommandResult)
    case commandNotFound(command: String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let result):
            let errorOutput = result.error.isEmpty ? result.output : result.error
            return "Command '\(result.command)' failed with exit code \(result.exitCode): \(errorOutput)"
        case .commandNotFound(let command):
            return "Command '\(command)' not found in PATH"
        }
    }
}
