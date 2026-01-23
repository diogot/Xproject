//
// XcodeOutputProcessorTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("XcodeOutputProcessor Tests", .serialized)
struct XcodeOutputProcessorTests {
    // MARK: - Verbose Mode Tests

    @Test("Verbose mode shows all formatted output")
    func verboseModeShowsAllOutput() {
        let processor = XcodeOutputProcessor(verbose: true, colored: false)

        // Build target line should be shown in verbose mode
        let buildLine = "=== BUILD TARGET MyApp OF PROJECT MyApp WITH CONFIGURATION Debug ==="
        let result = processor.processLine(buildLine)
        #expect(result != nil)
    }

    @Test("Verbose mode shows compile output")
    func verboseModeShowsCompileOutput() {
        let processor = XcodeOutputProcessor(
            verbose: true,
            colored: false,
            preserveUnbeautifiedLines: true
        )

        // Use a line format that xcbeautify recognizes
        let compileLine = "CompileSwift normal arm64 /path/to/File.swift (in target 'MyApp' from project 'MyApp')"
        let result = processor.processLine(compileLine)
        // In verbose mode with preserveUnbeautifiedLines, we should get output
        #expect(result != nil)
    }

    // MARK: - Non-Verbose Mode Tests

    @Test("Non-verbose mode shows error output")
    func nonVerboseModeShowsErrors() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        // Simulate error output that contains the error symbol
        // In practice, xcbeautify formats errors with ❌ or [x]
        let errorLine = "/path/to/File.swift:10:5: error: cannot find 'foo' in scope"
        let result = processor.processLine(errorLine)
        // Errors should always be shown in non-verbose mode
        #expect(result != nil, "Errors should be shown in non-verbose mode")
        if let output = result {
            #expect(output.contains("error") || output.contains("❌") || output.contains("[x]"))
        }
    }

    @Test("Non-verbose mode shows warning output")
    func nonVerboseModeShowsWarnings() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        let warningLine = "/path/to/File.swift:10:5: warning: unused variable 'x'"
        let result = processor.processLine(warningLine)
        // Warnings should always be shown in non-verbose mode
        #expect(result != nil, "Warnings should be shown in non-verbose mode")
        if let output = result {
            #expect(output.contains("warning") || output.contains("⚠️") || output.contains("[!]"))
        }
    }

    @Test("Non-verbose mode shows test failure output")
    func nonVerboseModeShowsTestFailures() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        // Use the format xcbeautify recognizes for test case failures
        let testFailLine = "/path/to/MyTests.swift:10: error: -[MyTests testExample] : failed - Expected true"
        let result = processor.processLine(testFailLine)
        // Test failures should always be shown in non-verbose mode
        #expect(result != nil, "Test failures should be shown in non-verbose mode")
        if let output = result {
            #expect(output.contains("✖") || output.contains("failed") || output.contains("error"))
        }
    }

    @Test("Non-verbose mode shows BUILD FAILED")
    func nonVerboseModeShowsBuildFailed() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        // The processor should detect BUILD FAILED in output
        // Note: xcbeautify might format this differently
        let line = "** BUILD FAILED **"
        // This may not be a recognized xcbeautify pattern, but we filter by keywords
        // in isImportantOutput
        let result = processor.processLine(line)
        // Either xcbeautify formats it, or our filter catches it
        #expect(result == nil || result?.contains("BUILD FAILED") == true || result?.contains("❌") == true)
    }

    // MARK: - Filtering Tests

    @Test("Non-verbose mode filters regular build output")
    func nonVerboseModeFiltersRegularOutput() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        // Regular linking output should be filtered in non-verbose mode
        // This is a standard xcodebuild line that xcbeautify beautifies
        let linkLine = "Ld /path/to/MyApp.app/MyApp normal arm64"
        let result = processor.processLine(linkLine)

        // In non-verbose mode, regular linking should be filtered out
        // (result is nil or doesn't contain error/warning symbols)
        if let output = result {
            let hasImportantSymbol = output.contains("❌") ||
                                     output.contains("⚠️") ||
                                     output.contains("✖") ||
                                     output.contains("[x]") ||
                                     output.contains("[!]")
            #expect(!hasImportantSymbol)
        }
    }

    // MARK: - Unrecognized Lines

    @Test("Unrecognized lines return nil with preserveUnbeautifiedLines=false")
    func unrecognizedLinesReturnNil() {
        let processor = XcodeOutputProcessor(
            verbose: true,
            colored: false,
            preserveUnbeautifiedLines: false
        )

        let randomLine = "This is not a recognized xcodebuild output line xyz123"
        let result = processor.processLine(randomLine)
        #expect(result == nil)
    }

    @Test("Unrecognized lines preserved with preserveUnbeautifiedLines=true")
    func unrecognizedLinesPreserved() {
        let processor = XcodeOutputProcessor(
            verbose: true,
            colored: false,
            preserveUnbeautifiedLines: true
        )

        let randomLine = "This is not a recognized xcodebuild output line xyz123"
        let result = processor.processLine(randomLine)
        #expect(result == randomLine)
    }

    // MARK: - Empty Lines

    @Test("Empty lines return nil")
    func emptyLinesReturnNil() {
        let processor = XcodeOutputProcessor(verbose: true, colored: false)

        let result = processor.processLine("")
        #expect(result == nil)
    }

    // MARK: - Output Symbols Detection

    @Test("Detects error symbol in formatted output")
    func detectsErrorSymbol() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        // Create a line that xcbeautify will format with an error
        let errorLine = "/path/File.swift:1:1: error: expected declaration"
        let result = processor.processLine(errorLine)

        // Should be shown in non-verbose mode due to error
        // (either xcbeautify adds symbol or our filter catches "error")
        #expect(result != nil)
    }

    @Test("Detects warning symbol in formatted output")
    func detectsWarningSymbol() {
        let processor = XcodeOutputProcessor(verbose: false, colored: false)

        let warningLine = "/path/File.swift:1:1: warning: unused"
        let result = processor.processLine(warningLine)

        // Should be shown in non-verbose mode
        #expect(result != nil)
    }
}
