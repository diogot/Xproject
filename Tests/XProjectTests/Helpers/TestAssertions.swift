//
// TestAssertions.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

/// Common test assertions for XProject tests
public struct TestAssertions {
    /// Asserts that a specific error type is thrown with an optional message check
    public static func assertThrows<E: Error>(
        _ errorType: E.Type,
        containingMessage message: String? = nil,
        when operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try operation()
            Issue.record("Expected \(errorType) to be thrown, but no error was thrown")
        } catch let error as E {
            if let message = message {
                let errorDescription = error.localizedDescription
                if !errorDescription.contains(message) {
                    Issue.record("Expected error message to contain '\(message)', but got: \(errorDescription)")
                }
            }
        } catch {
            Issue.record("Expected \(errorType), but got \(type(of: error)): \(error)")
        }
    }

    /// Asserts that no error is thrown
    public static func assertNoThrow<T>(
        _ operation: () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T? {
        do {
            return try operation()
        } catch {
            Issue.record("Expected no error, but got: \(error)")
            return nil
        }
    }

    /// Asserts that a command was executed with specific parameters
    public static func assertCommandExecuted(
        _ executor: MockCommandExecutor,
        command: String,
        containing substring: String? = nil,
        workingDirectory: URL? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let executedCommands = executor.executedCommands

        let matchingCommands = executedCommands.filter { cmd in
            var matches = cmd.command == command || (substring != nil && cmd.command.contains(substring!))

            if let expectedDir = workingDirectory {
                matches = matches && cmd.workingDirectory == expectedDir
            }

            return matches
        }

        if matchingCommands.isEmpty {
            let commandList = executedCommands.map { $0.command }.joined(separator: "\n  - ")
            let message = "Expected command '\(command)' \(substring.map { "containing '\($0)'" } ?? "") was not executed." +
                          " Executed commands:\n  - \(commandList)"
            Issue.record(Comment(rawValue: message))
        }
    }

    /// Asserts file system operations
    public static func assertDirectoryCreated(
        _ fileManager: MockFileManager,
        path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !fileManager.createdDirectories.contains(path) {
            Issue.record(
                "Expected directory '\(path)' to be created. Created directories: \(fileManager.createdDirectories)"
            )
        }
    }

    /// Asserts that a file or directory was removed
    public static func assertItemRemoved(
        _ fileManager: MockFileManager,
        path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !fileManager.removedItems.contains(path) {
            Issue.record(
                "Expected item '\(path)' to be removed. Removed items: \(fileManager.removedItems)"
            )
        }
    }

    /// Asserts array contains element matching predicate
    public static func assertContains<T>(
        _ array: [T],
        where predicate: (T) -> Bool,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !array.contains(where: predicate) {
            Issue.record(Comment(rawValue: message))
        }
    }
}
