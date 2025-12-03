//
// PRReportService.swift
// Xproject
//
// Service for posting build/test results to GitHub PRs
//
// swiftlint:disable file_length

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

    // swiftlint:disable:next function_body_length cyclomatic_complexity
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

        // Check GitHub context availability (unless explicitly dry-run)
        let (effectiveDryRun, skipReason) = dryRun ? (true, nil) : checkGitHubContextAvailability()

        // Aggregate stats across all xcresults
        var totalStats = Statistics()
        var allAnnotations: [Annotation] = []
        var allSummaries: [String] = []
        var overallConclusion: PRReportConclusion = .neutral

        // Process each xcresult separately
        for path in pathsToProcess {
            let absolutePath = resolvePath(path)
            guard FileManager.default.fileExists(atPath: absolutePath) else {
                throw PRReportError.xcresultNotFound(path: absolutePath)
            }

            let parser = XCResultParser(path: absolutePath)
            let result = try await parser.parse()

            // Collect results based on mode
            let buildResults: [BuildResults] = if let br = result.buildResults, !testOnly { [br] } else { [] }
            let testResults: [TestResults] = if let tr = result.testResults, !buildOnly { [tr] } else { [] }

            // Skip if no results
            guard !buildResults.isEmpty || !testResults.isEmpty else { continue }

            // Convert to annotations for this xcresult
            var annotations = convertToAnnotations(buildResults: buildResults, testResults: testResults)
            annotations = filterAnnotations(annotations)

            // Compute statistics for this xcresult
            let stats = computeStatistics(buildResults: buildResults, testResults: testResults)

            // Determine conclusion for this xcresult
            let conclusion = determineConclusion(stats: stats, annotations: annotations)

            // Extract description from xcresult data
            let description = extractDescription(
                path: absolutePath,
                buildResults: buildResults.first,
                testResults: testResults.first
            )

            // Generate summary for this xcresult
            let summary = generateSummary(
                stats: stats,
                buildResults: buildResults,
                testResults: testResults,
                description: description
            )

            // Accumulate totals
            totalStats.warnings += stats.warnings
            totalStats.errors += stats.errors
            totalStats.analyzerWarnings += stats.analyzerWarnings
            totalStats.testFailures += stats.testFailures
            totalStats.testsPassed += stats.testsPassed
            totalStats.testsSkipped += stats.testsSkipped
            allAnnotations.append(contentsOf: annotations)

            // Only include summary if it would actually be posted
            // When postSummary is false, we still post if there are annotations
            if config.postSummary || !annotations.isEmpty {
                allSummaries.append(summary)
            }

            // Update overall conclusion (failure takes precedence)
            if conclusion == .failure {
                overallConclusion = .failure
            } else if conclusion == .success && overallConclusion != .failure {
                overallConclusion = .success
            }

            // Report to GitHub (each xcresult gets its own comment)
            if !effectiveDryRun {
                let filename = (absolutePath as NSString).lastPathComponent
                    .replacingOccurrences(of: ".xcresult", with: "")
                let identifier = "xproject-pr-report-\(filename)"

                try await reportToGitHubWithIdentifier(
                    annotations: annotations,
                    summary: summary,
                    checkName: checkName ?? config.checkName ?? "Xcode Build & Test",
                    conclusion: conclusion,
                    identifier: identifier
                )
            }
        }

        // Combine all summaries for dry-run output
        let combinedSummary = allSummaries.joined(separator: "\n\n---\n\n")

        if effectiveDryRun {
            let annotationInfos = allAnnotations.map { annotation in
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
                annotationsPosted: allAnnotations.count,
                warningsCount: totalStats.warnings,
                errorsCount: totalStats.errors,
                testFailuresCount: totalStats.testFailures,
                testsPassedCount: totalStats.testsPassed,
                testsSkippedCount: totalStats.testsSkipped,
                conclusion: overallConclusion,
                summary: combinedSummary,
                annotations: annotationInfos,
                skipReason: skipReason
            )
        }

        return PRReportResult(
            checkRunURL: nil,
            annotationsPosted: allAnnotations.count,
            warningsCount: totalStats.warnings,
            errorsCount: totalStats.errors,
            testFailuresCount: totalStats.testFailures,
            testsPassedCount: totalStats.testsPassed,
            testsSkippedCount: totalStats.testsSkipped,
            conclusion: overallConclusion
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

    /// Check if GitHub context is available for posting.
    /// Returns (shouldDryRun, skipReason) tuple.
    private func checkGitHubContextAvailability() -> (Bool, PRReportResult.SkipReason?) {
        // Try to get GitHub context from environment
        do {
            let context = try GitHubContext.fromEnvironment()

            // Check if we have a PR number
            if context.pullRequest == nil {
                return (true, .missingPullRequestNumber)
            }

            // Check if this is a fork PR (read-only token)
            if context.isForkPR {
                return (true, .forkPR)
            }

            // Context is valid - can post to GitHub
            return (false, nil)
        } catch {
            // Failed to get context - not in GitHub Actions environment
            return (true, .notInGitHubActions)
        }
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

            // Read output BEFORE waiting to avoid pipe buffer deadlock
            // (if output exceeds ~64KB, the process blocks waiting to write)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            gitProcess.waitUntilExit()

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

    // swiftlint:disable cyclomatic_complexity
    /// Extract description from xcresult data (for footer display)
    /// Returns "Test {devices}" or "Build {destination}" based on the xcresult content
    func extractDescription(
        path: String,
        buildResults: BuildResults?,
        testResults: TestResults?
    ) -> String {
        // Determine action type based on which results are present
        let isTest = testResults != nil
        let actionPrefix = isTest ? "Test" : "Build"

        // Try to extract device info from test results
        if let testResults = testResults, !testResults.devices.isEmpty {
            let deviceDescriptions = testResults.devices.compactMap { device -> String? in
                let osVersion = device.osVersion ?? ""
                let deviceName = (device.deviceName ?? "").replacingOccurrences(of: " ", with: "")

                // Skip generic/placeholder device names (Any iOS Device, Any iOS Simulator Device, etc.)
                let lowerName = deviceName.lowercased()
                if lowerName.contains("any") && (lowerName.contains("simulator") || lowerName.contains("device")) {
                    return nil
                }

                // Build description based on what's available
                if !osVersion.isEmpty && !deviceName.isEmpty {
                    return "\(osVersion)_\(deviceName)"
                } else if !deviceName.isEmpty {
                    return deviceName
                } else if !osVersion.isEmpty {
                    return osVersion
                }
                return nil
            }
            if !deviceDescriptions.isEmpty {
                return "\(actionPrefix) \(deviceDescriptions.joined(separator: ", "))"
            }
        }

        // Fall back to parsing destination from filename
        let filename = (path as NSString).lastPathComponent.replacingOccurrences(of: ".xcresult", with: "")

        // Check for "archive-" prefix (e.g., "archive-dev-ios")
        if filename.hasPrefix("archive-") {
            let stripped = String(filename.dropFirst(8)) // remove "archive-"
            if !stripped.isEmpty {
                return "Archive \(stripped)"
            }
            return "Archive"
        }

        // Check for "-build" suffix (e.g., "tests-MyScheme-26.0_iPhone16Pro-build")
        if filename.hasSuffix("-build") {
            let stripped = String(filename.dropLast(6)) // remove "-build"
            let parts = stripped.split(separator: "-")
            if parts.count >= 2, let destination = parts.last {
                return "Build \(destination)"
            }
            return "Build"
        }

        // Parse destination from filename (e.g., "tests-MyScheme-26.0_iPhone16Pro")
        let parts = filename.split(separator: "-")
        if parts.count >= 3, let destination = parts.last {
            return "\(actionPrefix) \(destination)"
        }

        // Last resort: just the action type
        if testResults != nil || buildResults != nil {
            return actionPrefix
        }

        return ""
    }
    // swiftlint:enable cyclomatic_complexity

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
        testResults: [TestResults],
        description: String
    ) -> String {
        var lines: [String] = []

        // Collect all build issues with source locations (for inline display)
        let allBuildIssues = buildResults.flatMap { $0.allIssues }
        let issuesWithLocation = allBuildIssues.filter { $0.sourceLocation != nil }
        let errorsWithLocation = issuesWithLocation.filter { $0.severity == .failure }
        let warningsWithLocation = issuesWithLocation.filter { $0.severity == .warning }
        let noticesWithLocation = issuesWithLocation.filter { $0.severity == .notice }

        // Build warnings section (using table format)
        let totalWarnings = stats.warnings + stats.analyzerWarnings
        if totalWarnings > 0 {
            lines.append("| | **\(totalWarnings) Warning\(totalWarnings == 1 ? "" : "s")** |")
            lines.append("|---|---|")

            // Add warnings with source locations
            // Note: warningsWithLocation is pre-filtered, so location should always exist
            for warning in warningsWithLocation.prefix(10) {
                guard let location = warning.sourceLocation else { continue }
                let relativePath = location.relativePath(from: workingDirectory)
                let linkText = "\(relativePath)#L\(location.line)"
                lines.append("| :warning: | [\(linkText)](\(relativePath)#L\(location.line)): \(warning.message) |")
            }

            // Add notices/analyzer warnings
            // Note: noticesWithLocation is pre-filtered, so location should always exist
            for notice in noticesWithLocation.prefix(max(0, 10 - warningsWithLocation.count)) {
                guard let location = notice.sourceLocation else { continue }
                let relativePath = location.relativePath(from: workingDirectory)
                let linkText = "\(relativePath)#L\(location.line)"
                lines.append("| :warning: | [\(linkText)](\(relativePath)#L\(location.line)): \(notice.message) |")
            }

            let totalShown = min(10, warningsWithLocation.count + noticesWithLocation.count)
            let totalAvailable = warningsWithLocation.count + noticesWithLocation.count
            if totalAvailable > totalShown {
                let remaining = totalAvailable - totalShown
                lines.append("| | _...and \(remaining) more_ |")
            }
            lines.append("")
        }

        // Build errors section (using table format)
        if stats.errors > 0 {
            lines.append("| | **\(stats.errors) Error\(stats.errors == 1 ? "" : "s")** |")
            lines.append("|---|---|")

            // Note: errorsWithLocation is pre-filtered, so location should always exist
            for error in errorsWithLocation.prefix(10) {
                guard let location = error.sourceLocation else { continue }
                let relativePath = location.relativePath(from: workingDirectory)
                let linkText = "\(relativePath)#L\(location.line)"
                lines.append("| :x: | [\(linkText)](\(relativePath)#L\(location.line)): \(error.message) |")
            }

            if errorsWithLocation.count > 10 {
                let remaining = errorsWithLocation.count - 10
                lines.append("| | _...and \(remaining) more_ |")
            }
            lines.append("")
        }

        // Test results section (messages table)
        let totalTests = stats.testsPassed + stats.testFailures + stats.testsSkipped
        if totalTests > 0 {
            // Count messages (one per test target/summary)
            let messageCount = testResults.count
            if messageCount > 0 {
                lines.append("| | **\(messageCount) Message\(messageCount == 1 ? "" : "s")** |")
                lines.append("|---|---|")

                for result in testResults {
                    let summary = result.summary
                    let targetName = result.testNodes.first?.name ?? "Tests"
                    let expectedSuffix = summary.expectedFailureCount > 0
                        ? " (\(summary.expectedFailureCount) expected)"
                        : ""
                    // swiftlint:disable:next line_length
                    let message = "\(targetName): Executed \(summary.totalCount) test\(summary.totalCount == 1 ? "" : "s"), with \(summary.failedCount) failure\(summary.failedCount == 1 ? "" : "s")\(expectedSuffix)"
                    lines.append("| :book: | \(message) |")
                }
                lines.append("")
            }

            // List test failures
            let allFailures = testResults.flatMap { $0.failures }
            let collapsedFailures = config.collapseParallelTests
                ? collapseParallelTests(allFailures)
                : allFailures

            if !collapsedFailures.isEmpty {
                lines.append("| | **\(collapsedFailures.count) Test Failure\(collapsedFailures.count == 1 ? "" : "s")** |")
                lines.append("|---|---|")

                for failure in collapsedFailures.prefix(10) {
                    lines.append("| :x: | `\(failure.testClass).\(failure.testName)` |")
                }
                if collapsedFailures.count > 10 {
                    let remaining = collapsedFailures.count - 10
                    lines.append("| | _...and \(remaining) more_ |")
                }
                lines.append("")
            }
        }

        // No issues found
        if lines.isEmpty {
            lines.append("| | **Build & Test Results** |")
            lines.append("|---|---|")
            lines.append("| :white_check_mark: | All checks passed! |")
            lines.append("")
        }

        // Add description footer (right-aligned)
        if !description.isEmpty {
            lines.append("<p align=\"right\">\(description)</p>")
        }

        return lines.joined(separator: "\n")
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func reportToGitHubWithIdentifier(
        annotations: [Annotation],
        summary: String,
        checkName: String,
        conclusion: PRReportConclusion,
        identifier: String
    ) async throws {
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

        do {
            let commentReporter = PRCommentReporter(
                context: context,
                identifier: identifier,
                commentMode: .update
            )

            // Post summary comment if enabled, or if there are issues to report
            // When postSummary is false, we still post if there are annotations
            if config.postSummary || !annotations.isEmpty {
                try await commentReporter.postSummary(summary)
            } else {
                try await commentReporter.cleanup()
            }

            // Post inline annotations if enabled
            if config.inlineAnnotations {
                let reviewReporter = PRReviewReporter(
                    context: context,
                    identifier: identifier,
                    outOfRangeStrategy: .fallbackToComment
                )
                if !annotations.isEmpty {
                    _ = try await reviewReporter.report(annotations)
                } else {
                    // Clean up stale overflow comments when no annotations
                    try await reviewReporter.cleanup()
                }
            } else {
                // Clean up review comments when inline annotations disabled
                let reviewReporter = PRReviewReporter(
                    context: context,
                    identifier: identifier,
                    outOfRangeStrategy: .fallbackToComment
                )
                try await reviewReporter.cleanup()
            }
        } catch {
            throw PRReportError.reportingFailed(reason: error.localizedDescription)
        }
    }
}
