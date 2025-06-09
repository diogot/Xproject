//
// CommandExecutorTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

@Suite("Command Executor Tests")
struct CommandExecutorTests {
    // MARK: - Basic Execution Tests

    @Test("Basic command execution succeeds", .tags(.unit, .commandExecution, .fast))
    func basicCommandExecution() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo 'test'")

        #expect(result.exitCode == 0)
        #expect(result.output == "test")
        #expect(result.command == "echo 'test'")
        #expect(result.isSuccess)
    }

    @Test("Failed command execution is handled correctly", .tags(.unit, .commandExecution, .errorHandling, .fast))
    func failedCommandExecution() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("false") // Command that always fails

        #expect(result.exitCode == 1)
        #expect(!result.isSuccess)
        #expect(result.command == "false")
    }

    @Test("Command with output is captured correctly", .tags(.unit, .commandExecution, .fast))
    func commandWithOutput() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo 'hello world'")

        #expect(result.exitCode == 0)
        #expect(result.output == "hello world")
        #expect(result.error.isEmpty)
    }

    @Test("Command with error is captured correctly", .tags(.unit, .commandExecution, .fast))
    func commandWithError() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo 'error message' >&2")

        #expect(result.exitCode == 0)
        #expect(result.output.isEmpty)
        #expect(result.error == "error message")
    }

    @Test("Combined output from stdout and stderr", .tags(.unit, .commandExecution, .fast))
    func combinedOutput() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo 'stdout'; echo 'stderr' >&2")

        #expect(result.exitCode == 0)
        #expect(result.output == "stdout")
        #expect(result.error == "stderr")

        let combined = result.combinedOutput
        #expect(combined.contains("stdout"))
        #expect(combined.contains("stderr"))
    }

    // MARK: - Working Directory Tests

    @Test("Command executes in specified working directory", .tags(.unit, .commandExecution, .fast))
    func commandWithWorkingDirectory() throws {
        let executor = CommandExecutor()
        let tempDir = FileManager.default.temporaryDirectory
        let result = try executor.execute("pwd", workingDirectory: tempDir)

        #expect(result.exitCode == 0)
        #expect(result.output.contains(tempDir.path))
    }

    // MARK: - Environment Variable Tests

    @Test("Command uses provided environment variables", .tags(.unit, .commandExecution, .fast))
    func commandWithEnvironmentVariables() throws {
        let executor = CommandExecutor()
        let env = ["TEST_VAR": "test_value"]
        let result = try executor.execute("echo $TEST_VAR", environment: env)

        #expect(result.exitCode == 0)
        #expect(result.output == "test_value")
    }

    @Test("Environment variables can override system defaults", .tags(.unit, .commandExecution, .fast))
    func environmentVariableOverride() throws {
        let executor = CommandExecutor()
        let env = ["PATH": "/custom/path"]
        let result = try executor.execute("echo $PATH", environment: env)

        #expect(result.exitCode == 0)
        #expect(result.output.contains("/custom/path"))
    }

    // MARK: - ExecuteOrThrow Tests

    @Test("ExecuteOrThrow succeeds for successful commands", .tags(.unit, .commandExecution, .fast))
    func executeOrThrowSuccess() throws {
        let executor = CommandExecutor()
        let result = try executor.executeOrThrow("echo 'success'")

        #expect(result.exitCode == 0)
        #expect(result.output == "success")
    }

    @Test("ExecuteOrThrow throws for failed commands", .tags(.unit, .commandExecution, .errorHandling, .fast))
    func executeOrThrowFailure() throws {
        let executor = CommandExecutor()

        #expect(throws: CommandError.self) {
            try executor.executeOrThrow("false")
        }
    }

    // MARK: - Command Existence Tests

    @Test("Command existence detection works correctly", .tags(.unit, .commandExecution, .fast))
    func commandExists() {
        let executor = CommandExecutor()

        // Test with a command that should exist
        #expect(executor.commandExists("echo"))

        // Test with a command that should not exist
        #expect(!executor.commandExists("definitely_not_a_real_command_12345"))
    }

    // MARK: - Dry Run Tests

    @Test("Dry run mode mocks command execution", .tags(.unit, .dryRun, .fast))
    func dryRunMode() throws {
        let executor = CommandExecutor(dryRun: true)
        let result = try executor.execute("false") // Would normally fail

        #expect(result.exitCode == 0) // Should be mocked success
        #expect(result.output.isEmpty)
        #expect(result.error.isEmpty)
        #expect(result.command == "false")
        #expect(result.isSuccess)
    }

    @Test("Dry run works with working directory", .tags(.unit, .dryRun, .fast))
    func dryRunWithWorkingDirectory() throws {
        let executor = CommandExecutor(dryRun: true)
        let tempDir = FileManager.default.temporaryDirectory
        let result = try executor.execute("pwd", workingDirectory: tempDir)

        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
    }

    @Test("Dry run works with environment variables", .tags(.unit, .dryRun, .fast))
    func dryRunWithEnvironment() throws {
        let executor = CommandExecutor(dryRun: true)
        let env = ["TEST": "value"]
        let result = try executor.execute("echo $TEST", environment: env)

        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
    }

    @Test("Dry run assumes all commands exist", .tags(.unit, .dryRun, .fast))
    func dryRunCommandExists() {
        let executor = CommandExecutor(dryRun: true)

        // In dry run, should assume commands exist
        #expect(executor.commandExists("echo"))
        #expect(executor.commandExists("definitely_not_a_real_command"))
    }

    @Test("Dry run executeOrThrow never throws", .tags(.unit, .dryRun, .fast))
    func dryRunExecuteOrThrow() throws {
        let executor = CommandExecutor(dryRun: true)

        // Should not throw even for commands that would normally fail
        #expect(throws: Never.self) {
            try executor.executeOrThrow("false")
        }

        let result = try executor.executeOrThrow("false")
        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
    }

    // MARK: - Error Handling Tests

    @Test("Command error description contains relevant information", .tags(.unit, .errorHandling, .fast))
    func commandErrorDescription() {
        let result = CommandResult(exitCode: 1, output: "", error: "Command failed", command: "test")
        let error = CommandError.executionFailed(result: result)

        let description = error.localizedDescription
        #expect(description.contains("test"))
        #expect(description.contains("exit code 1"))
        #expect(description.contains("Command failed"))
    }

    @Test("Command not found error describes missing command", .tags(.unit, .errorHandling, .fast))
    func commandNotFoundError() {
        let error = CommandError.commandNotFound(command: "missing_command")
        let description = error.localizedDescription

        #expect(description.contains("missing_command"))
        #expect(description.contains("not found in PATH"))
    }

    // MARK: - CommandResult Tests

    @Test("CommandResult success detection works correctly", .tags(.unit, .fast))
    func commandResultIsSuccess() {
        let successResult = CommandResult(exitCode: 0, output: "", error: "", command: "test")
        #expect(successResult.isSuccess)

        let failureResult = CommandResult(exitCode: 1, output: "", error: "", command: "test")
        #expect(!failureResult.isSuccess)
    }

    @Test("CommandResult combined output handles all scenarios", .tags(.unit, .fast))
    func commandResultCombinedOutput() {
        // Test with only output
        let outputOnly = CommandResult(exitCode: 0, output: "output", error: "", command: "test")
        #expect(outputOnly.combinedOutput == "output")

        // Test with only error
        let errorOnly = CommandResult(exitCode: 0, output: "", error: "error", command: "test")
        #expect(errorOnly.combinedOutput == "error")

        // Test with both output and error
        let both = CommandResult(exitCode: 0, output: "output", error: "error", command: "test")
        #expect(both.combinedOutput == "output\nerror")

        // Test with neither
        let neither = CommandResult(exitCode: 0, output: "", error: "", command: "test")
        #expect(neither.combinedOutput.isEmpty)
    }

    // MARK: - Output Trimming Tests

    @Test("Output is properly trimmed of whitespace and newlines", .tags(.unit, .commandExecution, .fast))
    func outputTrimming() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo '  trimmed  '")

        #expect(result.output == "trimmed") // CommandExecutor trims whitespace and newlines

        // Test with actual whitespace trimming
        let resultWithNewlines = try executor.execute("echo 'test'; echo")
        #expect(!resultWithNewlines.output.hasSuffix("\n"))
    }

    // MARK: - Complex Command Tests

    @Test("Complex commands with multiple operations work correctly", .tags(.unit, .commandExecution, .fast))
    func complexCommand() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo 'hello' && echo 'world'")

        #expect(result.exitCode == 0)
        #expect(result.output.contains("hello"))
        #expect(result.output.contains("world"))
    }

    @Test("Pipe commands work correctly", .tags(.unit, .commandExecution, .fast))
    func pipeCommand() throws {
        let executor = CommandExecutor()
        let result = try executor.execute("echo 'hello world' | grep 'world'")

        #expect(result.exitCode == 0)
        #expect(result.output.contains("world"))
    }
}
