//
// Tag+TestTags.swift
// Xproject
//

import Testing

// MARK: - Test Tags for Organization and Filtering

extension Tag {
    /// Tests that verify individual units/components in isolation
    @Tag static var unit: Self

    /// Tests that verify integration between multiple components
    @Tag static var integration: Self

    /// Tests that verify thread safety and concurrent access patterns
    @Tag static var threading: Self

    /// Tests that verify dry-run functionality without side effects
    @Tag static var dryRun: Self

    /// Tests that involve file system operations or temporary files
    @Tag static var fileSystem: Self

    /// Tests that verify error handling and failure scenarios
    @Tag static var errorHandling: Self

    /// Tests that verify command execution and shell operations
    @Tag static var commandExecution: Self

    /// Tests that verify configuration loading and validation
    @Tag static var configuration: Self

    /// Fast tests that should run in CI for quick feedback
    @Tag static var fast: Self

    /// Tests that may be flaky or have timing dependencies
    @Tag static var flaky: Self

    /// Tests that verify Xcode client functionality
    @Tag static var xcodeClient: Self

    /// Tests that verify test service functionality
    @Tag static var testService: Self

    /// Tests that verify verbose output functionality
    @Tag static var verbose: Self

    /// Tests that verify streaming output functionality
    @Tag static var streaming: Self
}
