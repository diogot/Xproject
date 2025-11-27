//
// PRReportService.swift
// Xproject
//
// Service for posting build/test results to GitHub PRs
//

import Foundation
import PRReporterKit

// MARK: - PR Report Service Protocol

public protocol PRReportServiceProtocol: Sendable {
    func report(
        xcresultPaths: [String],
        checkName: String?,
        buildOnly: Bool,
        testOnly: Bool,
        dryRun: Bool
    ) async throws -> PRReportResult

    func discoverXcresultBundles() throws -> [String]
}

// MARK: - PR Report Service

// swiftlint:disable:next type_body_length
public final class PRReportService: PRReportServiceProtocol, Sendable {
    private let workingDirectory: String
    private let config: PRReportConfiguration
    private let reportsPath: String

    public init(
        workingDirectory: String,
        config: PRReportConfiguration,
        reportsPath: String
    ) {
        self.workingDirectory = workingDirectory
        self.config = config
        self.reportsPath = reportsPath
    }

    // MARK: - Public Methods

    // swiftlint:disable:next function_body_length
    public func report(
        xcresultPaths: [String],
        checkName: String?,
        buildOnly: Bool,
        testOnly: Bool,
        dryRun: Bool
    ) async throws -> PRReportResult {
        // Determine paths to process
        let pathsToProcess = xcresultPaths.isEmpty ? try discoverXcresultBundles() : xcresultPaths

        guard !pathsToProcess.isEmpty else {
            throw PRReportError.noXcresultBundles(directory: absoluteReportsPath())
        }

        // Parse all xcresult bundles
        var allBuildResults: [BuildResults] = []
        var allTestResults: [TestResults] = []

        for path in pathsToProcess {
            let absolutePath = resolvePath(path)
            guard FileManager.default.fileExists(atPath: absolutePath) else {
                throw PRReportError.xcresultNotFound(path: absolutePath)
            }

            let parser = XCResultParser(path: absolutePath)
            let result = try await parser.parse()

            if let buildResults = result.buildResults, !testOnly {
                allBuildResults.append(buildResults)
            }
            if let testResults = result.testResults, !buildOnly {
                allTestResults.append(testResults)
            }
        }

        // Convert to annotations
        var annotations = convertToAnnotations(
            buildResults: allBuildResults,
            testResults: allTestResults
        )

        // Apply filtering
        annotations = filterAnnotations(annotations)

        // Compute statistics
        let stats = computeStatistics(buildResults: allBuildResults, testResults: allTestResults)

        // Determine conclusion
        let conclusion = determineConclusion(stats: stats, annotations: annotations)

        // Generate summary
        let summary = generateSummary(stats: stats, testResults: allTestResults)

        if dryRun {
            return PRReportResult(
                checkRunURL: nil,
                annotationsPosted: annotations.count,
                warningsCount: stats.warnings,
                errorsCount: stats.errors,
                testFailuresCount: stats.testFailures,
                testsPassedCount: stats.testsPassed,
                testsSkippedCount: stats.testsSkipped,
                conclusion: conclusion
            )
        }

        // Report to GitHub
        let reportResult = try await reportToGitHub(
            annotations: annotations,
            summary: summary,
            checkName: checkName ?? config.checkName ?? "Xcode Build & Test",
            conclusion: conclusion
        )

        return PRReportResult(
            checkRunURL: reportResult.checkRunURL?.absoluteString,
            annotationsPosted: reportResult.annotationsPosted,
            warningsCount: stats.warnings,
            errorsCount: stats.errors,
            testFailuresCount: stats.testFailures,
            testsPassedCount: stats.testsPassed,
            testsSkippedCount: stats.testsSkipped,
            conclusion: conclusion
        )
    }

    public func discoverXcresultBundles() throws -> [String] {
        let reportsDir = absoluteReportsPath()

        guard FileManager.default.fileExists(atPath: reportsDir) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: reportsDir)
        return contents
            .filter { $0.hasSuffix(".xcresult") }
            .map { "\(reportsDir)/\($0)" }
            .sorted()
    }

    // MARK: - Private Methods

    private func absoluteReportsPath() -> String {
        if reportsPath.hasPrefix("/") {
            return reportsPath
        }
        return "\(workingDirectory)/\(reportsPath)"
    }

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return "\(workingDirectory)/\(path)"
    }

    private func convertToAnnotations(
        buildResults: [BuildResults],
        testResults: [TestResults]
    ) -> [Annotation] {
        var annotations: [Annotation] = []

        // Build issues
        for results in buildResults {
            for issue in results.allIssues {
                if let annotation = convertBuildIssueToAnnotation(issue) {
                    annotations.append(annotation)
                }
            }
        }

        // Test failures
        for results in testResults {
            let failures = config.collapseParallelTests
                ? collapseParallelTests(results.failures)
                : results.failures

            for failure in failures {
                if let annotation = convertTestFailureToAnnotation(failure) {
                    annotations.append(annotation)
                }
            }
        }

        return annotations
    }

    private func convertBuildIssueToAnnotation(_ issue: BuildIssue) -> Annotation? {
        guard let location = issue.sourceLocation else {
            return nil
        }

        let relativePath = location.relativePath(from: workingDirectory)
        let level: Annotation.Level = switch issue.severity {
        case .failure:
            .failure
        case .warning:
            .warning
        case .notice:
            .notice
        }

        return Annotation(
            path: relativePath,
            line: location.line,
            endLine: nil,
            column: location.column,
            level: level,
            message: issue.message,
            title: issue.issueType
        )
    }

    private func convertTestFailureToAnnotation(_ failure: TestFailure) -> Annotation? {
        guard let location = failure.sourceLocation else {
            return nil
        }

        let relativePath = location.relativePath(from: workingDirectory)

        return Annotation(
            path: relativePath,
            line: location.line,
            endLine: nil,
            column: location.column,
            level: .failure,
            message: failure.message,
            title: "\(failure.testClass).\(failure.testName)"
        )
    }

    private func filterAnnotations(_ annotations: [Annotation]) -> [Annotation] {
        var filtered = annotations

        // Filter by ignored files
        if let ignoredFiles = config.ignoredFiles, !ignoredFiles.isEmpty {
            filtered = filtered.filter { annotation in
                !matchesAnyGlobPattern(path: annotation.path, patterns: ignoredFiles)
            }
        }

        // Filter warnings if configured
        if config.ignoreWarnings {
            filtered = filtered.filter { $0.level != .warning }
        }

        return filtered
    }

    private func matchesAnyGlobPattern(path: String, patterns: [String]) -> Bool {
        patterns.contains { matchesGlobPattern(path: path, pattern: $0) }
    }

    private func matchesGlobPattern(path: String, pattern: String) -> Bool {
        // Convert glob to regex using placeholders to avoid replacement conflicts
        // (e.g., replacing ** with .* and then * with [^/]* would corrupt .*)
        let regexPattern = "^" + pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "**/", with: "\u{0000}DOUBLE_STAR_SLASH\u{0000}")
            .replacingOccurrences(of: "**", with: "\u{0000}DOUBLE_STAR\u{0000}")
            .replacingOccurrences(of: "*", with: "[^/]*")
            .replacingOccurrences(of: "\u{0000}DOUBLE_STAR_SLASH\u{0000}", with: "(.*/)?")
            .replacingOccurrences(of: "\u{0000}DOUBLE_STAR\u{0000}", with: ".*")
            + "$"

        return path.range(of: regexPattern, options: .regularExpression) != nil
    }

    private func collapseParallelTests(_ failures: [TestFailure]) -> [TestFailure] {
        var seen = Set<String>()
        return failures.filter { failure in
            let identifier = "\(failure.testClass).\(failure.testName)"
            if seen.contains(identifier) {
                return false
            }
            seen.insert(identifier)
            return true
        }
    }

    private struct Statistics {
        var warnings: Int = 0
        var errors: Int = 0
        var analyzerWarnings: Int = 0
        var testFailures: Int = 0
        var testsPassed: Int = 0
        var testsSkipped: Int = 0
    }

    private func computeStatistics(
        buildResults: [BuildResults],
        testResults: [TestResults]
    ) -> Statistics {
        var stats = Statistics()

        for results in buildResults {
            stats.warnings += results.warningCount
            stats.errors += results.errorCount
            stats.analyzerWarnings += results.analyzerWarningCount
        }

        for results in testResults {
            let summary = results.summary
            stats.testFailures += summary.failedCount
            stats.testsPassed += summary.passedCount
            stats.testsSkipped += summary.skippedCount
        }

        return stats
    }

    private func determineConclusion(stats: Statistics, annotations: [Annotation]) -> PRReportConclusion {
        let hasErrors = stats.errors > 0 && config.failOnErrors
        let hasTestFailures = stats.testFailures > 0 && config.failOnTestFailures

        if hasErrors || hasTestFailures {
            return .failure
        }

        if annotations.isEmpty && stats.testsPassed == 0 {
            return .neutral
        }

        return .success
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func generateSummary(stats: Statistics, testResults: [TestResults]) -> String {
        var lines: [String] = []

        // Build results section
        if stats.errors > 0 || stats.warnings > 0 || stats.analyzerWarnings > 0 {
            lines.append("## Build Results")
            lines.append("")
            if stats.errors > 0 {
                lines.append("- :x: **\(stats.errors) error\(stats.errors == 1 ? "" : "s")**")
            }
            if stats.warnings > 0 {
                lines.append("- :warning: **\(stats.warnings) warning\(stats.warnings == 1 ? "" : "s")**")
            }
            if stats.analyzerWarnings > 0 {
                let plural = stats.analyzerWarnings == 1 ? "" : "s"
                lines.append("- :information_source: **\(stats.analyzerWarnings) analyzer warning\(plural)**")
            }
            lines.append("")
        }

        // Test results section
        let totalTests = stats.testsPassed + stats.testFailures + stats.testsSkipped
        if totalTests > 0 {
            lines.append("## Test Results")
            lines.append("")
            if stats.testFailures > 0 {
                lines.append("- :x: **\(stats.testFailures) test\(stats.testFailures == 1 ? "" : "s") failed**")
            }
            lines.append("- :white_check_mark: \(stats.testsPassed) test\(stats.testsPassed == 1 ? "" : "s") passed")
            if stats.testsSkipped > 0 {
                lines.append("- :fast_forward: \(stats.testsSkipped) test\(stats.testsSkipped == 1 ? "" : "s") skipped")
            }
            lines.append("")

            // List failures
            let allFailures = testResults.flatMap { $0.failures }
            let collapsedFailures = config.collapseParallelTests
                ? collapseParallelTests(allFailures)
                : allFailures

            if !collapsedFailures.isEmpty {
                lines.append("### Failed Tests")
                lines.append("")
                for failure in collapsedFailures.prefix(10) {
                    lines.append("- `\(failure.testClass).\(failure.testName)`")
                }
                if collapsedFailures.count > 10 {
                    lines.append("")
                    lines.append("_...and \(collapsedFailures.count - 10) more failure\(collapsedFailures.count - 10 == 1 ? "" : "s")_")
                }
            }
        }

        // No issues found
        if lines.isEmpty {
            lines.append("## Build & Test Results")
            lines.append("")
            lines.append(":white_check_mark: All checks passed!")
        }

        return lines.joined(separator: "\n")
    }

    private func reportToGitHub(
        annotations: [Annotation],
        summary: String,
        checkName: String,
        conclusion: PRReportConclusion
    ) async throws -> ReportResult {
        let context: GitHubContext
        do {
            context = try GitHubContext.fromEnvironment()
        } catch {
            if let contextError = error as? ContextError {
                switch contextError {
                case .missingVariable(let name):
                    if name == "GITHUB_TOKEN" {
                        throw PRReportError.missingGitHubToken
                    }
                    throw PRReportError.notInGitHubActions
                case .readOnlyToken:
                    throw PRReportError.forkPRDetected
                default:
                    throw PRReportError.notInGitHubActions
                }
            }
            throw PRReportError.notInGitHubActions
        }

        // Check for fork PR
        if context.isForkPR {
            throw PRReportError.forkPRDetected
        }

        let reporter = CheckRunReporter(
            context: context,
            name: checkName,
            identifier: "xproject-pr-report"
        )

        let result: ReportResult
        do {
            if config.inlineAnnotations && !annotations.isEmpty {
                result = try await reporter.report(annotations)
            } else {
                result = ReportResult(annotationsPosted: 0, annotationsUpdated: 0, annotationsDeleted: 0, checkRunURL: nil, commentURL: nil)
            }

            if config.postSummary {
                try await reporter.postSummary(summary)
            }
        } catch {
            throw PRReportError.reportingFailed(reason: error.localizedDescription)
        }

        return result
    }
}
