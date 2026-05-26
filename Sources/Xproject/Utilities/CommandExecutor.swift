//
// CommandExecutor.swift
// Xproject
//

import Foundation
import Synchronization

// swiftlint:disable:next type_body_length
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

    // MARK: - Synchronous execution

    @discardableResult
    public func execute(_ command: String, environment: [String: String]? = nil) throws -> CommandResult {
        if dryRun {
            printEnvironmentBlock(environment)
            print("[DRY RUN] Would run: \(command)")
            return dryRunResult(command: command)
        }
        if verbose {
            printVerboseCommandInfo(command: command, environment: environment)
        }
        let process = makeBashProcess(command: command, environment: environment)
        return try runCollecting(process: process, command: command)
    }

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

    /// Read-only commands always execute, even in dry-run mode (used for discovery).
    @discardableResult
    public func executeReadOnly(
        _ command: String,
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        if verbose {
            printVerboseCommandInfo(command: command, environment: environment)
        }
        let process = makeBashProcess(command: command, environment: environment)
        return try runCollecting(process: process, command: command)
    }

    /// Execute a command with arguments array (safer than shell string interpolation)
    @discardableResult
    public func executeWithArguments(
        command: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        let fullCommand = ([command] + arguments).joined(separator: " ")

        if dryRun {
            printEnvironmentBlock(environment)
            print("[DRY RUN] Would run: \(fullCommand)")
            return dryRunResult(command: fullCommand)
        }
        if verbose {
            printVerboseCommandInfo(command: fullCommand, environment: environment)
        }
        let process = makeProcess(executable: command, arguments: arguments, environment: environment)
        return try runCollecting(process: process, command: fullCommand)
    }

    public func commandExists(_ command: String) -> Bool {
        do {
            return try executeReadOnly("which \(command)").exitCode == 0
        } catch {
            return false
        }
    }

    public func withWorkingDirectory(_ path: String) -> CommandExecuting {
        CommandExecutor(workingDirectory: path, dryRun: dryRun, verbose: verbose)
    }

    // MARK: - Asynchronous streaming execution

    @discardableResult
    public func executeWithStreamingOutput(
        _ command: String,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        if dryRun {
            printEnvironmentBlock(environment)
            print("[DRY RUN] Would run with streaming output: \(command)")
            return dryRunResult(command: command)
        }
        // Streaming output is always verbose-like: print the command line.
        printVerboseCommandInfo(command: command, environment: environment)
        let process = makeBashProcess(command: command, environment: environment)
        return try await runStreaming(process: process, command: command, lineProcessor: nil)
    }

    /// Execute a command with line-by-line processing through a custom processor.
    /// Each stdout line is passed to the processor; non-nil returns are printed.
    @discardableResult
    public func executeWithLineProcessor(
        _ command: String,
        environment: [String: String]? = nil,
        processor: @escaping @Sendable (String) -> String?
    ) async throws -> CommandResult {
        if dryRun {
            printEnvironmentBlock(environment)
            print("[DRY RUN] Would run with streaming output: \(command)")
            return dryRunResult(command: command)
        }
        printVerboseCommandInfo(command: command, environment: environment)
        let process = makeBashProcess(command: command, environment: environment)
        return try await runStreaming(process: process, command: command, lineProcessor: processor)
    }

    // MARK: - Process construction

    private func makeBashProcess(command: String, environment: [String: String]?) -> Process {
        makeProcess(executable: "/bin/bash", arguments: ["-c", command], environment: environment)
    }

    private func makeProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }
        return process
    }

    // MARK: - Synchronous drain core

    /// Drains stdout and stderr concurrently via `readabilityHandler` + `DispatchGroup`,
    /// then waits for process termination. Avoids the macOS pipe-buffer deadlock that
    /// happens when `waitUntilExit()` is called before the output pipes are read — the
    /// child blocks writing once a buffer (~64KB) fills and the parent blocks waiting
    /// for the child to exit. Apple DTS guidance:
    /// https://developer.apple.com/forums/thread/690310
    private func runCollecting(process: Process, command: String) throws -> CommandResult {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let group = DispatchGroup()
        let outBuf = LockedData()
        let errBuf = LockedData()
        let tee = verbose

        Self.drain(pipe: outPipe, into: outBuf, group: group, tee: tee ? .stdout : nil)
        Self.drain(pipe: errPipe, into: errBuf, group: group, tee: tee ? .stderr : nil)

        try process.run()
        process.waitUntilExit()
        group.wait()
        // Ensure all queued tee writes have flushed before returning, so callers
        // that immediately exit (e.g. CLI entry points) don't drop tail output.
        Self.teeQueue.sync {}

        return makeResult(
            out: outBuf.snapshot(),
            err: errBuf.snapshot(),
            exit: process.terminationStatus,
            command: command
        )
    }

    private enum TeeTarget: Sendable {
        case stdout
        case stderr
    }

    private static func drain(
        pipe: Pipe,
        into buffer: LockedData,
        group: DispatchGroup,
        tee: TeeTarget?
    ) {
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = readChunk(from: handle)
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                buffer.append(chunk)
                if let tee {
                    write(chunk, to: tee)
                }
            }
        }
    }

    /// Bounded by one pipe buffer's worth on macOS (~64KB). The kernel never
    /// returns more than the pipe holds, so a larger `upToCount` would not gain
    /// throughput — and a much larger value risks unhelpful buffer sizing inside
    /// Foundation. The readabilityHandler will be re-invoked for any remaining
    /// bytes.
    private static let readChunkSize = 64 * 1_024

    /// Use `read(upToCount:)` instead of `availableData` to avoid the spurious
    /// zero-byte callbacks documented in SR-14669. The API returns `nil` at EOF;
    /// a thrown error has no recovery path from inside a `readabilityHandler`
    /// callback, so we log it to the parent's stderr and treat it as EOF —
    /// terminating the drain is safer than spinning on the same failing fd.
    private static func readChunk(from handle: FileHandle) -> Data {
        do {
            return try handle.read(upToCount: readChunkSize) ?? Data()
        } catch {
            let message = "CommandExecutor: pipe read error (treating as EOF): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return Data()
        }
    }

    /// Serial queue used to tee child output to the parent's stdout/stderr in
    /// `verbose` mode. Writes are dispatched asynchronously so a slow consumer
    /// of the parent's stdout cannot block the `readabilityHandler` — which
    /// would let the child's pipe fill and recreate the deadlock the rest of
    /// this file works to avoid.
    private static let teeQueue = DispatchQueue(
        label: "com.diogot.xproject.CommandExecutor.tee",
        qos: .utility
    )

    private static func write(_ data: Data, to target: TeeTarget) {
        teeQueue.async {
            switch target {
            case .stdout:
                FileHandle.standardOutput.write(data)
            case .stderr:
                FileHandle.standardError.write(data)
            }
        }
    }

    private func makeResult(out: Data, err: Data, exit: Int32, command: String) -> CommandResult {
        let output = (String(data: out, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let error = (String(data: err, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(exitCode: exit, output: output, error: error, command: command)
    }

    private func dryRunResult(command: String) -> CommandResult {
        CommandResult(exitCode: 0, output: "", error: "", command: command)
    }

    // MARK: - Asynchronous drain core

    /// Runs the process, draining stdout/stderr through `AsyncStream`s. Termination
    /// is signalled by the readabilityHandler EOF callback that finishes each stream;
    /// the task group then returns and `waitUntilExit()` collects the exit status.
    /// We intentionally do NOT finish the continuations from a fallback task tied to
    /// `waitUntilExit`, which would race the final readabilityHandler dispatch and
    /// drop tail bytes.
    private func runStreaming(
        process: Process,
        command: String,
        lineProcessor: (@Sendable (String) -> String?)?
    ) async throws -> CommandResult {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = DataCollector()
        let lineBuffer = LineBuffer()

        let outStream = makeAsyncStream(for: outPipe)
        let errStream = makeAsyncStream(for: errPipe)

        try process.run()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                if let processor = lineProcessor {
                    await Self.consumeStdoutLines(
                        outStream, collector: collector, lineBuffer: lineBuffer, processor: processor
                    )
                } else {
                    await Self.consumeStdoutRaw(outStream, collector: collector)
                }
            }
            group.addTask {
                await Self.consumeStderr(errStream, collector: collector)
            }
        }

        process.waitUntilExit()
        let (outData, errData) = await collector.getData()
        return makeResult(out: outData, err: errData, exit: process.terminationStatus, command: command)
    }

    private static func consumeStdoutRaw(
        _ stream: AsyncStream<Data>,
        collector: DataCollector
    ) async {
        for await data in stream {
            await collector.appendOutput(data)
            if let text = String(data: data, encoding: .utf8) {
                print(text, terminator: "")
                fflush(stdout)
            }
        }
    }

    private static func consumeStdoutLines(
        _ stream: AsyncStream<Data>,
        collector: DataCollector,
        lineBuffer: LineBuffer,
        processor: @Sendable (String) -> String?
    ) async {
        for await data in stream {
            await collector.appendOutput(data)
            if let text = String(data: data, encoding: .utf8) {
                let lines = await lineBuffer.append(text)
                for line in lines {
                    if let processed = processor(line) {
                        print(processed)
                        fflush(stdout)
                    }
                }
            }
        }
        if let remaining = await lineBuffer.flush(), let processed = processor(remaining) {
            print(processed)
            fflush(stdout)
        }
    }

    private static func consumeStderr(
        _ stream: AsyncStream<Data>,
        collector: DataCollector
    ) async {
        for await data in stream {
            await collector.appendError(data)
            if let text = String(data: data, encoding: .utf8) {
                fputs(text, stderr)
                fflush(stderr)
            }
        }
    }

    private func makeAsyncStream(for pipe: Pipe) -> AsyncStream<Data> {
        AsyncStream<Data> { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = Self.readChunk(from: handle)
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            continuation.onTermination = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }
    }

    // MARK: - Verbose / dry-run helpers

    private func printEnvironmentBlock(_ environment: [String: String]?) {
        guard let environment, !environment.isEmpty else {
            return
        }
        print("Environment:")
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            let isSensitive = Self.sensitiveEnvPatterns.contains { key.uppercased().contains($0) }
            let displayValue = isSensitive ? "***" : value
            print("  \(key)=\(displayValue)")
        }
    }

    private func printVerboseCommandInfo(command: String, environment: [String: String]?) {
        printEnvironmentBlock(environment)
        print("$ \(command)")
    }
}

// MARK: - Command Execution Utilities

/// Synchronously-accessible thread-safe Data buffer used to collect pipe chunks
/// from `readabilityHandler` callbacks (which run on a background queue) without
/// the async hops that an actor would impose.
private final class LockedData: Sendable {
    private let mutex = Mutex<Data>(Data())

    func append(_ data: Data) {
        mutex.withLock { $0.append(data) }
    }

    func snapshot() -> Data {
        mutex.withLock { $0 }
    }
}

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
