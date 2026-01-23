//
// XcodeOutputProcessor.swift
// Xproject
//

import Foundation
@preconcurrency import XcbeautifyLib

/// Processes xcodebuild output using XcbeautifyLib for formatting.
///
/// In verbose mode, all formatted output is displayed.
/// In non-verbose mode, only errors, warnings, and test results are shown.
///
/// Note: This class uses `@unchecked Sendable` because `XCBeautifier` doesn't conform to
/// `Sendable`. This is safe because the processor is created fresh for each xcodebuild
/// execution and the beautifier's internal state (Parser/Formatter) is only accessed
/// synchronously through `processLine`.
public final class XcodeOutputProcessor: @unchecked Sendable {
    private let beautifier: XCBeautifier
    private let verbose: Bool

    /// Symbols used by xcbeautify for different output types.
    /// Used to detect output importance when filtering in non-verbose mode.
    private enum OutputSymbol {
        static let error = "❌"
        static let asciiError = "[x]"
        static let warning = "⚠️"
        static let asciiWarning = "[!]"
        static let testFail = "✖"
        static let testPass = "✔"
        static let testPending = "⧖"
        static let testCompletion = "▸"
        static let testMeasure = "◷"
        static let testSkipped = "⊘"
    }

    /// Creates a new XcodeOutputProcessor.
    /// - Parameters:
    ///   - verbose: If true, all formatted output is shown. If false, only errors, warnings, and test results.
    ///   - colored: If true, output includes ANSI color codes.
    ///   - preserveUnbeautifiedLines: If true, lines that can't be parsed are preserved as-is.
    ///   - additionalLines: Closure to provide additional lines for multi-line output parsing.
    public init(
        verbose: Bool,
        colored: Bool = true,
        preserveUnbeautifiedLines: Bool = false,
        additionalLines: @escaping @Sendable () -> String? = { nil }
    ) {
        self.verbose = verbose
        self.beautifier = XCBeautifier(
            colored: colored,
            renderer: .terminal,
            preserveUnbeautifiedLines: preserveUnbeautifiedLines,
            additionalLines: additionalLines
        )
    }

    /// Processes a single line of xcodebuild output.
    /// - Parameter line: Raw xcodebuild output line.
    /// - Returns: Formatted output if it should be displayed, nil otherwise.
    public func processLine(_ line: String) -> String? {
        guard let formatted = beautifier.format(line: line) else {
            return nil
        }

        if verbose {
            return formatted
        }

        // In non-verbose mode, only show important output
        return isImportantOutput(formatted) ? formatted : nil
    }

    /// Determines if formatted output is important enough to show in non-verbose mode.
    /// Important output includes: errors, warnings, and test results.
    private func isImportantOutput(_ output: String) -> Bool {
        // Errors
        if output.contains(OutputSymbol.error) || output.contains(OutputSymbol.asciiError) {
            return true
        }

        // Warnings
        if output.contains(OutputSymbol.warning) || output.contains(OutputSymbol.asciiWarning) {
            return true
        }

        // Test failures
        if output.contains(OutputSymbol.testFail) {
            return true
        }

        // Test summary/completion (e.g., "Executed X tests...")
        if output.contains(OutputSymbol.testCompletion) {
            return true
        }

        // Test suite results (passed/failed counts)
        if output.contains("passed") && output.contains("failed") {
            return true
        }

        // Build phase completion with errors/warnings
        if output.contains("BUILD FAILED") || output.contains("BUILD SUCCEEDED") {
            return true
        }

        return false
    }
}
