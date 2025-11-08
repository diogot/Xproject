//
// CommandExecutor.swift
// Xproject
//

import Foundation

public struct CommandExecutor: CommandExecuting, Sendable {
    private let workingDirectory: String
    internal let dryRun: Bool
    internal let verbose: Bool

    // Patterns for sensitive environment variables that should be masked in output
    private static let sensitiveEnvPatterns = [
        "PASSWORD", "PASS", "SECRET", "TOKEN", "KEY", "API",
        "PRIVATE", "AUTH", "CREDENTIAL", "SIGNING", "CERT", "CERTIFICATE",
        "JWT", "OAUTH", "BEARER", "ACCESS"
    ]

    public init(workingDirectory: String, dryRun: Bool = false, verbose: Bool = false) {
        self.workingDirectory = workingDirectory
        self.dryRun = dryRun
        self.verbose = verbose
    }

    /// Execute a shell command and return the result
    @discardableResult
    public func execute(_ command: String, environment: [String: String]? = nil) throws -> CommandResult {
        let workingDirectoryURL = URL(fileURLWithPath: self.workingDirectory)

        if dryRun {
            printEnvironmentBlock(environment)
            print("[DRY RUN] Would run: \(command)")

            // Return mock successful result for dry run
            return CommandResult(
                exitCode: 0,
                output: "",
                error: "",
                command: command
            )
        }

        if verbose {
            printVerboseCommandInfo(command: command, workingDirectory: workingDirectoryURL, environment: environment)
        }

        let process = Process()

        // Set command
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        // Set working directory
        process.currentDirectoryURL = workingDirectoryURL

        // Set environment
        if let environment = environment {
            var processEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                processEnvironment[key] = value
            }
            process.environment = processEnvironment
        }

        // Setup output capture
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Execute
        try process.run()
        process.waitUntilExit()

        // Capture output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return CommandResult(
            exitCode: process.terminationStatus,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            error: error.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command
        )
    }

    /// Execute a command and throw if it fails
    @discardableResult
    public func executeOrThrow(
        _ command: String,
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        let result = try execute(command, environment: environment)

        if result.exitCode != 0 {
            throw CommandError.executionFailed(result: result)
        }

        return result
    }

    /// Execute a read-only command that bypasses dry-run mode (for discovery operations)
    @discardableResult
    public func executeReadOnly(
        _ command: String,
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        // Read-only commands always execute, even in dry-run mode
        let workingDirectoryURL = URL(fileURLWithPath: self.workingDirectory)

        let process = Process()

        // Set command
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        // Set working directory
        process.currentDirectoryURL = workingDirectoryURL

        // Set environment
        if let environment = environment {
            var processEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                processEnvironment[key] = value
            }
            process.environment = processEnvironment
        }

        // Setup output capture
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Execute
        try process.run()
        process.waitUntilExit()

        // Capture output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return CommandResult(
            exitCode: process.terminationStatus,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            error: error.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command
        )
    }

    /// Create and configure a Process for command execution
    private func createProcess(
        command: String,
        environment: [String: String]?
    ) -> Process {
        let workingDirectoryURL = URL(fileURLWithPath: self.workingDirectory)

        let process = Process()

        // Set command
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        // Set working directory
        process.currentDirectoryURL = workingDirectoryURL

        // Set environment
        if let environment = environment {
            var processEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                processEnvironment[key] = value
            }
            process.environment = processEnvironment
        }

        return process
    }

    /// Handle dry run mode for streaming output
    private func handleDryRunStreamingOutput(
        command: String,
        environment: [String: String]?
    ) -> CommandResult {
        printEnvironmentBlock(environment)
        print("[DRY RUN] Would run with streaming output: \(command)")

        return CommandResult(
            exitCode: 0,
            output: "",
            error: "",
            command: command
        )
    }

    /// Create CommandResult from process and data
    private func createCommandResult(
        from process: Process,
        outputData: Data,
        errorData: Data,
        command: String
    ) -> CommandResult {
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return CommandResult(
            exitCode: process.terminationStatus,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            error: error.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command
        )
    }

    /// Print environment variables in block format with sensitive values masked
    private func printEnvironmentBlock(_ environment: [String: String]?) {
        guard let environment = environment, !environment.isEmpty else {
            return
        }

        print("Environment:")
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            let isSensitive = Self.sensitiveEnvPatterns.contains {
                key.uppercased().contains($0)
            }
            let displayValue = isSensitive ? "***" : value
            print("  \(key)=\(displayValue)")
        }
    }

    /// Print verbose command information
    private func printVerboseCommandInfo(command: String, workingDirectory: URL, environment: [String: String]?) {
        printEnvironmentBlock(environment)
        print("$ \(command)")
    }

    /// Execute a command with streaming output (async version using AsyncStream)
    @discardableResult
    public func executeWithStreamingOutput(
        _ command: String,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        let workingDirectoryURL = URL(fileURLWithPath: self.workingDirectory)

        if dryRun {
            return handleDryRunStreamingOutput(command: command, environment: environment)
        }

        // Always print command info for streaming output (verbose-like behavior)
        printVerboseCommandInfo(command: command, workingDirectory: workingDirectoryURL, environment: environment)

        let process = createProcess(command: command, environment: environment)
        let (outputData, errorData) = try await executeProcessWithStreamingAsync(process)

        return createCommandResult(
            from: process,
            outputData: outputData,
            errorData: errorData,
            command: command
        )
    }

    /// Execute process with streaming output using AsyncStream
    /// - Throws: An error if the process fails to launch
    private func executeProcessWithStreamingAsync(_ process: Process) async throws -> (Data, Data) {
        let (outputPipe, errorPipe) = setupProcessPipes(process)
        let collector = DataCollector()

        // Create streams that will be manually finished
        let (outputStream, outputContinuation) = createManagedAsyncStream(for: outputPipe)
        let (errorStream, errorContinuation) = createManagedAsyncStream(for: errorPipe)

        try process.run()

        // Process streams concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await data in outputStream {
                    if let string = String(data: data, encoding: .utf8) {
                        print(string, terminator: "")
                        fflush(stdout)
                    }
                    await collector.appendOutput(data)
                }
            }

            group.addTask {
                for await data in errorStream {
                    if let string = String(data: data, encoding: .utf8) {
                        fputs(string, stderr)
                        fflush(stderr)
                    }
                    await collector.appendError(data)
                }
            }

            group.addTask {
                // Wait for process to complete, then finish streams
                process.waitUntilExit()
                outputContinuation.finish()
                errorContinuation.finish()
            }
        }

        await collectRemainingData(outputPipe: outputPipe, errorPipe: errorPipe, collector: collector)

        return await collector.getData()
    }

    /// Setup pipes for process output and error streams
    private func setupProcessPipes(_ process: Process) -> (Pipe, Pipe) {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        return (outputPipe, errorPipe)
    }

    /// Create a managed async stream with external control over termination
    private func createManagedAsyncStream(for pipe: Pipe) -> (AsyncStream<Data>, AsyncStream<Data>.Continuation) {
        var storedContinuation: AsyncStream<Data>.Continuation?

        let stream = AsyncStream<Data> { continuation in
            storedContinuation = continuation

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    continuation.yield(data)
                }
                // Don't finish on empty data - will be finished externally
            }

            continuation.onTermination = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        guard let continuation = storedContinuation else {
            fatalError("Continuation should be set immediately in AsyncStream initialization")
        }
        return (stream, continuation)
    }

    /// Collect any remaining data from pipes after process completion
    private func collectRemainingData(outputPipe: Pipe, errorPipe: Pipe, collector: DataCollector) async {
        let remainingOutputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingErrorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        await collector.appendOutput(remainingOutputData)
        await collector.appendError(remainingErrorData)
    }

    /// Check if a command exists in PATH
    public func commandExists(_ command: String) -> Bool {
        do {
            let result = try executeReadOnly("which \(command)")
            return result.exitCode == 0
        } catch {
            return false
        }
    }
}

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

// MARK: - Command Errors

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

// MARK: - Command Execution Utilities

/// Actor for thread-safe data collection during streaming command execution
private actor DataCollector {
    var outputData = Data()
    var errorData = Data()

    func appendOutput(_ data: Data) {
        outputData.append(data)
    }

    func appendError(_ data: Data) {
        errorData.append(data)
    }

    func getData() -> (Data, Data) {
        (outputData, errorData)
    }
}
