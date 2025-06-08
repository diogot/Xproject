import Foundation

// MARK: - Command Execution Utilities

public struct CommandExecutor: Sendable {
    public init() {}
    
    /// Execute a shell command and return the result
    @discardableResult
    public func execute(_ command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> CommandResult {
        let process = Process()
        
        // Set command
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        // Set working directory
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        
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
    public func executeOrThrow(_ command: String, workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> CommandResult {
        let result = try execute(command, workingDirectory: workingDirectory, environment: environment)
        
        if result.exitCode != 0 {
            throw CommandError.executionFailed(result: result)
        }
        
        return result
    }
    
    /// Check if a command exists in PATH
    public func commandExists(_ command: String) -> Bool {
        do {
            let result = try execute("which \(command)")
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
            return "Command '\(result.command)' failed with exit code \(result.exitCode): \(result.error.isEmpty ? result.output : result.error)"
        case .commandNotFound(let command):
            return "Command '\(command)' not found in PATH"
        }
    }
}