//
// TestEnvironment.swift
// XProject
//

import Foundation

/// Utility for detecting test environment and adapting test behavior accordingly
public struct TestEnvironment {
    /// Detects if tests are running in a CI environment
    public static var isCI: Bool {
        return ProcessInfo.processInfo.environment["CI"] != nil ||
               ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil ||
               ProcessInfo.processInfo.environment["CONTINUOUS_INTEGRATION"] != nil
    }

    /// Detects if tests should run in fast mode (reduced delays and concurrency)
    public static var isFastMode: Bool {
        return ProcessInfo.processInfo.environment["XPROJECT_FAST_TESTS"] != nil
    }

    /// Returns appropriate task count for concurrency tests based on environment
    public static func concurrencyTaskCount(local: Int = 10, ci: Int = 5) -> Int {
        return isCI ? ci : local
    }

    /// Returns appropriate delay for test stability based on environment
    public static func stabilityDelay(local: TimeInterval = 0.001, ci: TimeInterval = 0.005) -> TimeInterval {
        guard !isFastMode else {
            return 0
        }
        return isCI ? ci : local
    }

    /// Returns appropriate timeout for async operations based on environment
    public static func operationTimeout(local: TimeInterval = 2, ci: TimeInterval = 5) -> TimeInterval {
        return isCI ? ci : local
    }

    /// Executes a block with retry logic for CI stability
    public static func withRetry<T>(
        attempts: Int = 3,
        delay: TimeInterval = 0.01,
        operation: () throws -> T
    ) throws -> T {
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try operation()
            } catch {
                lastError = error
                if attempt < attempts {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }

        throw lastError!
    }

    /// Executes an async block with retry logic for CI stability
    public static func withAsyncRetry<T>(
        attempts: Int = 3,
        delay: TimeInterval = 0.01,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError!
    }
}

/// Timeout support for async operations
public extension TestEnvironment {
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private struct TimeoutError: Error {}
}
