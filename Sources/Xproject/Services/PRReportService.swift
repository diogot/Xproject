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
    private let _reportsPath: String

    /// The configured reports path (may be relative or absolute)
    public var reportsPath: String { _reportsPath }

    public init(
        workingDirectory: String,
        config: PRReportConfiguration,
        reportsPath: String
    ) {
        self.workingDirectory = workingDirectory
        self.config = config
        self._reportsPath = reportsPath
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
        let summary = generateSummary(stats: stats, buildResults: allBuildResults, testResults: allTestResults)

        if dryRun {
            let annotationInfos = annotations.map { annotation in
                AnnotationInfo(
                    path: annotation.path,
                    line: annotation.line,
                    column: annotation.column,
                    level: convertLevel(annotation.level),
                    message: annotation.message,
                    title: annotation.title
                )
            }
            return PRReportResult(
                checkRunURL: nil,
                annotationsPosted: annotations.count,
                warningsCount: stats.warnings,
                errorsCount: stats.errors,
                testFailuresCount: stats.testFailures,
                testsPassedCount: stats.testsPassed,
                testsSkippedCount: stats.testsSkipped,
                conclusion: conclusion,
                summary: summary,
                annotations: annotationInfos
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
        if _reportsPath.hasPrefix("/") {
            return _reportsPath
        }
        return "\(workingDirectory)/\(_reportsPath)"
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

        // Build file index for resolving test failure paths
        // Test failures only contain the filename, so we need to find the full relative path
        let swiftFiles = discoverSwiftFiles()

        // Test failures
        for results in testResults {
            let failures = config.collapseParallelTests
                ? collapseParallelTests(results.failures)
                : results.failures

            for failure in failures {
                if let annotation = convertTestFailureToAnnotation(failure, swiftFiles: swiftFiles) {
                    annotations.append(annotation)
                }
            }
        }

        return annotations
    }

    /// Discover all Swift files in the working directory using git ls-files
    private func discoverSwiftFiles() -> [String: String] {
        // Build a map of filename -> relative path
        var fileMap: [String: String] = [:]

        // Try git ls-files first (faster and only tracked files)
        let gitProcess = Process()
        gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitProcess.arguments = ["ls-files", "*.swift", "**/*.swift"]
        gitProcess.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        gitProcess.standardOutput = pipe
        gitProcess.standardError = FileHandle.nullDevice

        do {
            try gitProcess.run()
            gitProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    let relativePath = String(line)
                    let filename = (relativePath as NSString).lastPathComponent
                    // Only store first match (in case of duplicate filenames)
                    if fileMap[filename] == nil {
                        fileMap[filename] = relativePath
                    }
                }
            }
        } catch {
            // Git not available, fall back to FileManager
            if let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: workingDirectory),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard fileURL.pathExtension == "swift" else { continue }
                    let relativePath = fileURL.path.replacingOccurrences(
                        of: workingDirectory + "/",
                        with: ""
                    )
                    let filename = fileURL.lastPathComponent
                    if fileMap[filename] == nil {
                        fileMap[filename] = relativePath
                    }
                }
            }
        }

        return fileMap
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

    private func convertTestFailureToAnnotation(
        _ failure: TestFailure,
        swiftFiles: [String: String]
    ) -> Annotation? {
        guard let location = failure.sourceLocation else {
            return nil
        }

        // Test failures only contain the filename, not the full path
        // Try to resolve using the swift files map
        let filename = (location.file as NSString).lastPathComponent
        let resolvedPath: String
        if let fullPath = swiftFiles[filename] {
            resolvedPath = fullPath
        } else {
            // Fall back to relative path calculation (works for absolute paths)
            resolvedPath = location.relativePath(from: workingDirectory)
        }

        return Annotation(
            path: resolvedPath,
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

    func matchesAnyGlobPattern(path: String, patterns: [String]) -> Bool {
        patterns.contains { matchesGlobPattern(path: path, pattern: $0) }
    }

    func matchesGlobPattern(path: String, pattern: String) -> Bool {
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

    private func convertLevel(_ level: Annotation.Level) -> AnnotationInfo.Level {
        switch level {
        case .failure:
            return .failure
        case .warning:
            return .warning
        case .notice:
            return .notice
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func generateSummary(
        stats: Statistics,
        buildResults: [BuildResults],
        testResults: [TestResults]
    ) -> String {
        var lines: [String] = []

        // Collect all build issues
        let allBuildIssues = buildResults.flatMap { $0.allIssues }
        let issuesWithoutLocation = allBuildIssues.filter { $0.sourceLocation == nil }
        let errorsWithoutLocation = issuesWithoutLocation.filter { $0.severity == .failure }
        let warningsWithoutLocation = issuesWithoutLocation.filter { $0.severity == .warning }
        let noticesWithoutLocation = issuesWithoutLocation.filter { $0.severity == .notice }

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

            // List errors without source location (these can't be posted as annotations)
            if !errorsWithoutLocation.isEmpty {
                lines.append("### Errors")
                lines.append("")
                for error in errorsWithoutLocation.prefix(10) {
                    let target = error.targetName.map { " (\($0))" } ?? ""
                    lines.append("- \(error.message)\(target)")
                }
                if errorsWithoutLocation.count > 10 {
                    lines.append("")
                    let remaining = errorsWithoutLocation.count - 10
                    lines.append("_...and \(remaining) more error\(remaining == 1 ? "" : "s")_")
                }
                lines.append("")
            }

            // List warnings without source location
            if !warningsWithoutLocation.isEmpty {
                lines.append("### Warnings")
                lines.append("")
                for warning in warningsWithoutLocation.prefix(10) {
                    let target = warning.targetName.map { " (\($0))" } ?? ""
                    lines.append("- \(warning.message)\(target)")
                }
                if warningsWithoutLocation.count > 10 {
                    lines.append("")
                    let remaining = warningsWithoutLocation.count - 10
                    lines.append("_...and \(remaining) more warning\(remaining == 1 ? "" : "s")_")
                }
                lines.append("")
            }

            // List notices without source location
            if !noticesWithoutLocation.isEmpty {
                lines.append("### Notices")
                lines.append("")
                for notice in noticesWithoutLocation.prefix(10) {
                    let target = notice.targetName.map { " (\($0))" } ?? ""
                    lines.append("- \(notice.message)\(target)")
                }
                if noticesWithoutLocation.count > 10 {
                    lines.append("")
                    let remaining = noticesWithoutLocation.count - 10
                    lines.append("_...and \(remaining) more notice\(remaining == 1 ? "" : "s")_")
                }
                lines.append("")
            }
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

        var result = ReportResult(
            annotationsPosted: 0,
            annotationsUpdated: 0,
            annotationsDeleted: 0,
            checkRunURL: nil,
            commentURL: nil
        )

        do {
            let commentReporter = PRCommentReporter(
                context: context,
                identifier: "xproject-pr-report",
                commentMode: .update
            )

            // Post summary comment if enabled, otherwise cleanup old comments
            if config.postSummary {
                try await commentReporter.postSummary(summary)
            } else {
                try await commentReporter.cleanup()
            }

            // Post inline annotations if enabled
            if config.inlineAnnotations {
                let reviewReporter = PRReviewReporter(
                    context: context,
                    identifier: "xproject-pr-report",
                    outOfRangeStrategy: .fallbackToComment
                )
                if !annotations.isEmpty {
                    result = try await reviewReporter.report(annotations)
                } else {
                    // Clean up stale overflow comments when no annotations
                    try await reviewReporter.cleanup()
                }
            } else {
                // Clean up overflow comment when inline annotations disabled
                let overflowReporter = PRCommentReporter(
                    context: context,
                    identifier: "xproject-pr-report-overflow",
                    commentMode: .update
                )
                try await overflowReporter.cleanup()
            }
        } catch {
            throw PRReportError.reportingFailed(reason: error.localizedDescription)
        }

        return result
    }
}
