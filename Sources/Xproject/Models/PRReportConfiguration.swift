//
// PRReportConfiguration.swift
// Xproject
//
// Configuration models for PR report integration
//

import Foundation

// MARK: - PR Report Configuration

/// Configuration for PR report integration
///
/// Loaded from the `pr_report:` section in Xproject.yml, this defines how
/// build/test results are reported to GitHub PRs via the Checks API.
public struct PRReportConfiguration: Codable, Sendable {
    /// Name for the GitHub Check Run (default: "Xcode Build & Test")
    public let checkName: String?

    /// Whether to post a summary comment (when false, still posts if there are issues)
    public let postSummary: Bool

    /// Whether to post inline annotations
    public let inlineAnnotations: Bool

    /// Whether to fail the check run if build errors exist
    public let failOnErrors: Bool

    /// Whether to fail the check run if test failures exist
    public let failOnTestFailures: Bool

    /// Glob patterns for files to ignore (e.g., ["Pods/**", "**/Generated/**"])
    public let ignoredFiles: [String]?

    /// Whether to ignore warnings (only report errors)
    public let ignoreWarnings: Bool

    /// Whether to collapse parallel test runs into single entries
    public let collapseParallelTests: Bool

    public init(
        checkName: String? = nil,
        postSummary: Bool = true,
        inlineAnnotations: Bool = true,
        failOnErrors: Bool = true,
        failOnTestFailures: Bool = true,
        ignoredFiles: [String]? = nil,
        ignoreWarnings: Bool = false,
        collapseParallelTests: Bool = true
    ) {
        self.checkName = checkName
        self.postSummary = postSummary
        self.inlineAnnotations = inlineAnnotations
        self.failOnErrors = failOnErrors
        self.failOnTestFailures = failOnTestFailures
        self.ignoredFiles = ignoredFiles
        self.ignoreWarnings = ignoreWarnings
        self.collapseParallelTests = collapseParallelTests
    }

    enum CodingKeys: String, CodingKey {
        case checkName = "check_name"
        case postSummary = "post_summary"
        case inlineAnnotations = "inline_annotations"
        case failOnErrors = "fail_on_errors"
        case failOnTestFailures = "fail_on_test_failures"
        case ignoredFiles = "ignored_files"
        case ignoreWarnings = "ignore_warnings"
        case collapseParallelTests = "collapse_parallel_tests"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkName = try container.decodeIfPresent(String.self, forKey: .checkName)
        postSummary = try container.decodeIfPresent(Bool.self, forKey: .postSummary) ?? true
        inlineAnnotations = try container.decodeIfPresent(Bool.self, forKey: .inlineAnnotations) ?? true
        failOnErrors = try container.decodeIfPresent(Bool.self, forKey: .failOnErrors) ?? true
        failOnTestFailures = try container.decodeIfPresent(Bool.self, forKey: .failOnTestFailures) ?? true
        ignoredFiles = try container.decodeIfPresent([String].self, forKey: .ignoredFiles)
        ignoreWarnings = try container.decodeIfPresent(Bool.self, forKey: .ignoreWarnings) ?? false
        collapseParallelTests = try container.decodeIfPresent(Bool.self, forKey: .collapseParallelTests) ?? true
    }
}

// MARK: - PR Report Result

/// Result of a PR report operation
public struct PRReportResult: Sendable {
    /// URL to the GitHub Check Run (if created)
    public let checkRunURL: String?

    /// Number of annotations posted
    public let annotationsPosted: Int

    /// Number of warnings found
    public let warningsCount: Int

    /// Number of errors found
    public let errorsCount: Int

    /// Number of test failures found
    public let testFailuresCount: Int

    /// Number of tests that passed
    public let testsPassedCount: Int

    /// Number of tests that were skipped
    public let testsSkippedCount: Int

    /// Conclusion of the check run
    public let conclusion: PRReportConclusion

    /// Summary markdown (populated in dry-run mode)
    public let summary: String?

    /// Annotations that would be posted (populated in dry-run mode)
    public let annotations: [AnnotationInfo]?

    public init(
        checkRunURL: String? = nil,
        annotationsPosted: Int = 0,
        warningsCount: Int = 0,
        errorsCount: Int = 0,
        testFailuresCount: Int = 0,
        testsPassedCount: Int = 0,
        testsSkippedCount: Int = 0,
        conclusion: PRReportConclusion = .neutral,
        summary: String? = nil,
        annotations: [AnnotationInfo]? = nil
    ) {
        self.checkRunURL = checkRunURL
        self.annotationsPosted = annotationsPosted
        self.warningsCount = warningsCount
        self.errorsCount = errorsCount
        self.testFailuresCount = testFailuresCount
        self.testsPassedCount = testsPassedCount
        self.testsSkippedCount = testsSkippedCount
        self.conclusion = conclusion
        self.summary = summary
        self.annotations = annotations
    }
}

// MARK: - Annotation Info

/// Simplified annotation info for display purposes
public struct AnnotationInfo: Sendable {
    /// File path relative to working directory
    public let path: String

    /// Line number
    public let line: Int

    /// Column number (optional)
    public let column: Int?

    /// Severity level
    public let level: Level

    /// Annotation message
    public let message: String

    /// Annotation title (e.g., test name or issue type)
    public let title: String?

    public enum Level: String, Sendable {
        case failure
        case warning
        case notice
    }

    public init(
        path: String,
        line: Int,
        column: Int? = nil,
        level: Level,
        message: String,
        title: String? = nil
    ) {
        self.path = path
        self.line = line
        self.column = column
        self.level = level
        self.message = message
        self.title = title
    }
}

// MARK: - PR Report Conclusion

/// Conclusion status for PR report
public enum PRReportConclusion: String, Sendable {
    case success
    case failure
    case neutral
}

// MARK: - PR Report Error

/// Errors that can occur during PR reporting
public enum PRReportError: Error, LocalizedError, Sendable {
    case prReportNotEnabled
    case notInGitHubActions
    case missingGitHubToken
    case xcresultNotFound(path: String)
    case noXcresultBundles(directory: String)
    case parsingFailed(path: String, reason: String)
    case reportingFailed(reason: String)
    case noResultsToReport
    case forkPRDetected

    public var errorDescription: String? {
        switch self {
        case .prReportNotEnabled:
            return """
            PR reporting is not configured.

            Add pr_report section to Xproject.yml:
               pr_report:
                 check_name: "Xcode Build & Test"
            """

        case .notInGitHubActions:
            return """
            PR reporting requires GitHub Actions environment.

            This command should be run in a GitHub Actions workflow.
            Required environment variables:
            - GITHUB_TOKEN
            - GITHUB_REPOSITORY
            - GITHUB_SHA
            """

        case .missingGitHubToken:
            return """
            GITHUB_TOKEN environment variable is required.

            In your GitHub Actions workflow, add:
               env:
                 GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            """

        case .xcresultNotFound(let path):
            return "xcresult bundle not found at: \(path)"

        case .noXcresultBundles(let directory):
            return """
            No xcresult bundles found in: \(directory)

            Run 'xp test' or 'xp build' first to generate xcresult bundles.
            """

        case let .parsingFailed(path, reason):
            return """
            Failed to parse xcresult bundle at: \(path)

            Reason: \(reason)
            """

        case .reportingFailed(let reason):
            return "Failed to report to GitHub: \(reason)"

        case .noResultsToReport:
            return "No build or test results found in xcresult bundle(s)"

        case .forkPRDetected:
            return """
            Cannot post annotations on fork PRs.

            Fork PRs have read-only GITHUB_TOKEN and cannot create check runs.
            """
        }
    }
}
