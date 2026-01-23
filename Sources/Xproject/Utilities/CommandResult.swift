//
// CommandResult.swift
// Xproject
//

import Foundation

// MARK: - Command Result

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String
    public let error: String
    public let command: String

    public var isSuccess: Bool {
        return exitCode == 0
    }

    public var combinedOutput: String {
        if error.isEmpty {
            return output
        } else if output.isEmpty {
            return error
        } else {
            return "\(output)\n\(error)"
        }
    }
}
