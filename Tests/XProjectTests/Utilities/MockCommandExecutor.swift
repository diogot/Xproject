//
// MockCommandExecutor.swift
// XProject
//

import Foundation
@testable import XProject

// MARK: - Mock Command Executor for Testing

public final class MockCommandExecutor: CommandExecuting, @unchecked Sendable {
    public struct ExecutedCommand: Sendable {
        public let command: String
        public let workingDirectory: URL?
        public let environment: [String: String]?

        public init(command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.environment = environment
        }
    }

    public struct MockResponse: Sendable {
        public let exitCode: Int32
        public let output: String
        public let error: String

        public init(exitCode: Int32 = 0, output: String = "", error: String = "") {
            self.exitCode = exitCode
            self.output = output
            self.error = error
        }

        public static let success = MockResponse(exitCode: 0)
        public static let failure = MockResponse(exitCode: 1, error: "Command failed")
    }

    private let lock = NSLock()
    private var _executedCommands: [ExecutedCommand] = []
    private var _responses: [String: MockResponse] = [:]
    private var _defaultResponse: MockResponse = .success
    private var _commandExists: [String: Bool] = [:]

    public init() {}

    // MARK: - Configuration Methods

    public func setResponse(for command: String, response: MockResponse) {
        lock.lock()
        defer { lock.unlock() }
        _responses[command] = response
    }

    public func setDefaultResponse(_ response: MockResponse) {
        lock.lock()
        defer { lock.unlock() }
        _defaultResponse = response
    }

    public func setCommandExists(_ command: String, exists: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _commandExists[command] = exists
    }

    // MARK: - Verification Methods

    public var executedCommands: [ExecutedCommand] {
        lock.lock()
        defer { lock.unlock() }
        return _executedCommands
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _executedCommands.removeAll()
        _responses.removeAll()
        _commandExists.removeAll()
        _defaultResponse = .success
    }

    public func wasCommandExecuted(_ command: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _executedCommands.contains { $0.command == command }
    }

    public func commandExecutionCount(_ command: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _executedCommands.filter { $0.command == command }.count
    }

    public func lastExecutedCommand() -> ExecutedCommand? {
        lock.lock()
        defer { lock.unlock() }
        return _executedCommands.last
    }

    // MARK: - Mock Implementation

    public func execute(_ command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> CommandResult {
        lock.lock()
        defer { lock.unlock() }

        // Record the executed command
        let executedCommand = ExecutedCommand(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment
        )
        _executedCommands.append(executedCommand)

        // Get response for this command
        let response = _responses[command] ?? _defaultResponse

        return CommandResult(
            exitCode: response.exitCode,
            output: response.output,
            error: response.error,
            command: command
        )
    }

    public func executeOrThrow(
        _ command: String,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        let result = try execute(command, workingDirectory: workingDirectory, environment: environment)

        if result.exitCode != 0 {
            throw CommandError.executionFailed(result: result)
        }

        return result
    }

    public func commandExists(_ command: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Record this as an executed command for verification
        let executedCommand = ExecutedCommand(command: "which \(command)")
        _executedCommands.append(executedCommand)

        return _commandExists[command] ?? true // Default to exists
    }
}

// MARK: - Test Helper Extensions

public extension MockCommandExecutor {
    /// Set up common brew command responses for setup testing
    func setupBrewMocks() {
        setCommandExists("brew", exists: true)
        setResponse(for: "brew update", response: .success)
        setResponse(for: "( brew list swiftgen ) && ( brew outdated swiftgen || brew upgrade swiftgen ) || ( brew install swiftgen )",
                    response: MockResponse(exitCode: 0, output: "swiftgen installed"))
        setResponse(for: "( brew list swiftlint ) && ( brew outdated swiftlint || brew upgrade swiftlint ) || ( brew install swiftlint )",
                    response: MockResponse(exitCode: 0, output: "swiftlint installed"))
    }

    /// Set up failure scenarios for testing error handling
    func setupBrewFailureMocks() {
        setCommandExists("brew", exists: false)
        setResponse(for: "brew update", response: MockResponse(exitCode: 1, error: "Network error"))
        setResponse(for: "( brew list swiftgen ) && ( brew outdated swiftgen || brew upgrade swiftgen ) || ( brew install swiftgen )",
                    response: MockResponse(exitCode: 1, error: "Formula not found"))
    }
}
