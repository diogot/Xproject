//
// PRReportServiceTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject
import Yams

@Suite("PRReportService Tests")
struct PRReportServiceTests {
    // MARK: - Instantiation Tests

    @Test("PRReportService can be instantiated", .tags(.unit, .prReport))
    func instantiation() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(
            workingDirectory: "/tmp",
            config: config,
            reportsPath: "reports"
        )
        #expect(type(of: service) == PRReportService.self)
    }

    // MARK: - discoverXcresultBundles Tests

    @Test("discoverXcresultBundles returns empty array when directory does not exist", .tags(.unit, .prReport, .fileSystem))
    func discoverXcresultBundlesNonExistentDirectory() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(
            workingDirectory: "/nonexistent/path",
            config: config,
            reportsPath: "reports"
        )

        let bundles = try service.discoverXcresultBundles()
        #expect(bundles.isEmpty)
    }

    @Test("discoverXcresultBundles finds xcresult files", .tags(.unit, .prReport, .fileSystem))
    func discoverXcresultBundlesFindsFiles() throws {
        try TestFileHelper.withTemporaryDirectory { tempDir in
            // Create some xcresult files
            let reportsDir = tempDir.appendingPathComponent("reports")
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

            let xcresult1 = reportsDir.appendingPathComponent("Test1.xcresult")
            let xcresult2 = reportsDir.appendingPathComponent("Test2.xcresult")
            try "dummy".write(to: xcresult1, atomically: true, encoding: .utf8)
            try "dummy".write(to: xcresult2, atomically: true, encoding: .utf8)

            // Create a non-xcresult file to ensure it's filtered out
            let otherFile = reportsDir.appendingPathComponent("other.txt")
            try "dummy".write(to: otherFile, atomically: true, encoding: .utf8)

            let config = PRReportConfiguration()
            let service = PRReportService(
                workingDirectory: tempDir.path,
                config: config,
                reportsPath: "reports"
            )

            let bundles = try service.discoverXcresultBundles()
            #expect(bundles.count == 2)
            #expect(bundles.allSatisfy { $0.hasSuffix(".xcresult") })
        }
    }

    @Test("discoverXcresultBundles returns sorted results", .tags(.unit, .prReport, .fileSystem))
    func discoverXcresultBundlesSortedResults() throws {
        try TestFileHelper.withTemporaryDirectory { tempDir in
            let reportsDir = tempDir.appendingPathComponent("reports")
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

            // Create files with names that would be unsorted
            let xcresult1 = reportsDir.appendingPathComponent("Zeta.xcresult")
            let xcresult2 = reportsDir.appendingPathComponent("Alpha.xcresult")
            let xcresult3 = reportsDir.appendingPathComponent("Beta.xcresult")
            try "dummy".write(to: xcresult1, atomically: true, encoding: .utf8)
            try "dummy".write(to: xcresult2, atomically: true, encoding: .utf8)
            try "dummy".write(to: xcresult3, atomically: true, encoding: .utf8)

            let config = PRReportConfiguration()
            let service = PRReportService(
                workingDirectory: tempDir.path,
                config: config,
                reportsPath: "reports"
            )

            let bundles = try service.discoverXcresultBundles()
            #expect(bundles.count == 3)
            #expect(bundles[0].hasSuffix("Alpha.xcresult"))
            #expect(bundles[1].hasSuffix("Beta.xcresult"))
            #expect(bundles[2].hasSuffix("Zeta.xcresult"))
        }
    }

    @Test("discoverXcresultBundles handles absolute reports path", .tags(.unit, .prReport, .fileSystem))
    func discoverXcresultBundlesAbsolutePath() throws {
        try TestFileHelper.withTemporaryDirectory { tempDir in
            let reportsDir = tempDir.appendingPathComponent("absolute-reports")
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

            let xcresult = reportsDir.appendingPathComponent("Test.xcresult")
            try "dummy".write(to: xcresult, atomically: true, encoding: .utf8)

            let config = PRReportConfiguration()
            let service = PRReportService(
                workingDirectory: "/different/path",
                config: config,
                reportsPath: reportsDir.path  // Absolute path
            )

            let bundles = try service.discoverXcresultBundles()
            #expect(bundles.count == 1)
        }
    }

    // MARK: - Glob Pattern Matching Tests

    @Test("Glob pattern matches simple wildcard", .tags(.unit, .prReport))
    func globPatternSimpleWildcard() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(workingDirectory: "/tmp", config: config, reportsPath: "reports")

        // *.swift should match files in current directory only
        #expect(service.matchesGlobPattern(path: "File.swift", pattern: "*.swift"))
        #expect(service.matchesGlobPattern(path: "AnotherFile.swift", pattern: "*.swift"))
        #expect(!service.matchesGlobPattern(path: "Dir/File.swift", pattern: "*.swift"))
        #expect(!service.matchesGlobPattern(path: "File.txt", pattern: "*.swift"))
    }

    @Test("Glob pattern matches double-star recursive", .tags(.unit, .prReport))
    func globPatternDoubleStarRecursive() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(workingDirectory: "/tmp", config: config, reportsPath: "reports")

        // **/*.swift should match files at any depth
        #expect(service.matchesGlobPattern(path: "File.swift", pattern: "**/*.swift"))
        #expect(service.matchesGlobPattern(path: "Dir/File.swift", pattern: "**/*.swift"))
        #expect(service.matchesGlobPattern(path: "Dir/Sub/File.swift", pattern: "**/*.swift"))
        #expect(!service.matchesGlobPattern(path: "File.txt", pattern: "**/*.swift"))
    }

    @Test("Glob pattern matches prefix with double-star", .tags(.unit, .prReport))
    func globPatternPrefixDoubleStart() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(workingDirectory: "/tmp", config: config, reportsPath: "reports")

        // Pods/** should match all files under Pods/
        #expect(service.matchesGlobPattern(path: "Pods/Something.swift", pattern: "Pods/**"))
        #expect(service.matchesGlobPattern(path: "Pods/Sub/File.swift", pattern: "Pods/**"))
        #expect(service.matchesGlobPattern(path: "Pods/A/B/C/File.swift", pattern: "Pods/**"))
        #expect(!service.matchesGlobPattern(path: "NotPods/File.swift", pattern: "Pods/**"))
        #expect(!service.matchesGlobPattern(path: "SomePods/File.swift", pattern: "Pods/**"))
    }

    @Test("Glob pattern escapes dots correctly", .tags(.unit, .prReport))
    func globPatternEscapesDots() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(workingDirectory: "/tmp", config: config, reportsPath: "reports")

        // Dots should be literal, not regex wildcards
        #expect(service.matchesGlobPattern(path: "File.swift", pattern: "*.swift"))
        #expect(!service.matchesGlobPattern(path: "Fileswift", pattern: "*.swift"))
        #expect(service.matchesGlobPattern(path: "test.xcodeproj", pattern: "*.xcodeproj"))
    }

    @Test("Glob pattern matches intermediate directories", .tags(.unit, .prReport))
    func globPatternIntermediateDirectories() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(workingDirectory: "/tmp", config: config, reportsPath: "reports")

        // **/Generated/** should match files in Generated at any level
        #expect(service.matchesGlobPattern(path: "Generated/File.swift", pattern: "**/Generated/**"))
        #expect(service.matchesGlobPattern(path: "Dir/Generated/File.swift", pattern: "**/Generated/**"))
        #expect(service.matchesGlobPattern(path: "A/B/Generated/C/File.swift", pattern: "**/Generated/**"))
        #expect(!service.matchesGlobPattern(path: "NotGenerated/File.swift", pattern: "**/Generated/**"))
    }

    @Test("Glob pattern matchesAnyGlobPattern works with multiple patterns", .tags(.unit, .prReport))
    func globPatternMatchesAny() throws {
        let config = PRReportConfiguration()
        let service = PRReportService(workingDirectory: "/tmp", config: config, reportsPath: "reports")

        let patterns = ["Pods/**", "**/Generated/**", "*.generated.swift"]

        #expect(service.matchesAnyGlobPattern(path: "Pods/File.swift", patterns: patterns))
        #expect(service.matchesAnyGlobPattern(path: "Dir/Generated/File.swift", patterns: patterns))
        #expect(service.matchesAnyGlobPattern(path: "Types.generated.swift", patterns: patterns))
        #expect(!service.matchesAnyGlobPattern(path: "Sources/Main.swift", patterns: patterns))
    }
}

// MARK: - PRReportConfiguration Tests

@Suite("PRReportConfiguration Tests")
struct PRReportConfigurationTests {
    @Test("Default configuration has expected values", .tags(.unit, .prReport, .configuration))
    func defaultConfiguration() throws {
        let config = PRReportConfiguration()
        #expect(config.checkName == nil)
        #expect(config.postSummary == true)
        #expect(config.inlineAnnotations == true)
        #expect(config.failOnErrors == true)
        #expect(config.failOnTestFailures == true)
        #expect(config.ignoredFiles == nil)
        #expect(config.ignoreWarnings == false)
        #expect(config.collapseParallelTests == true)
    }

    @Test("Configuration can be created with custom values", .tags(.unit, .prReport, .configuration))
    func customConfiguration() throws {
        let config = PRReportConfiguration(
            checkName: "Custom Check",
            postSummary: false,
            inlineAnnotations: false,
            failOnErrors: false,
            failOnTestFailures: false,
            ignoredFiles: ["Pods/**"],
            ignoreWarnings: true,
            collapseParallelTests: false
        )

        #expect(config.checkName == "Custom Check")
        #expect(config.postSummary == false)
        #expect(config.inlineAnnotations == false)
        #expect(config.failOnErrors == false)
        #expect(config.failOnTestFailures == false)
        #expect(config.ignoredFiles == ["Pods/**"])
        #expect(config.ignoreWarnings == true)
        #expect(config.collapseParallelTests == false)
    }

    @Test("Configuration decodes from YAML with defaults", .tags(.unit, .prReport, .configuration))
    func configurationDecodesWithDefaults() throws {
        let yaml = """
        check_name: Test Check
        """
        let data = yaml.data(using: .utf8)!
        let decoder = YAMLDecoder()
        let config = try decoder.decode(PRReportConfiguration.self, from: data)

        #expect(config.checkName == "Test Check")
        #expect(config.postSummary == true)
        #expect(config.inlineAnnotations == true)
        #expect(config.failOnErrors == true)
        #expect(config.failOnTestFailures == true)
        #expect(config.ignoreWarnings == false)
        #expect(config.collapseParallelTests == true)
    }

    @Test("Configuration decodes from YAML with custom values", .tags(.unit, .prReport, .configuration))
    func configurationDecodesWithCustomValues() throws {
        let yaml = """
        check_name: My Custom Check
        post_summary: false
        inline_annotations: false
        fail_on_errors: false
        fail_on_test_failures: false
        ignored_files:
          - "Pods/**"
          - "**/Generated/**"
        ignore_warnings: true
        collapse_parallel_tests: false
        """
        let data = yaml.data(using: .utf8)!
        let decoder = YAMLDecoder()
        let config = try decoder.decode(PRReportConfiguration.self, from: data)

        #expect(config.checkName == "My Custom Check")
        #expect(config.postSummary == false)
        #expect(config.inlineAnnotations == false)
        #expect(config.failOnErrors == false)
        #expect(config.failOnTestFailures == false)
        #expect(config.ignoredFiles == ["Pods/**", "**/Generated/**"])
        #expect(config.ignoreWarnings == true)
        #expect(config.collapseParallelTests == false)
    }
}

// MARK: - PRReportResult Tests

@Suite("PRReportResult Tests")
struct PRReportResultTests {
    @Test("Default result has expected values", .tags(.unit, .prReport))
    func defaultResult() throws {
        let result = PRReportResult()
        #expect(result.checkRunURL == nil)
        #expect(result.annotationsPosted == 0)
        #expect(result.warningsCount == 0)
        #expect(result.errorsCount == 0)
        #expect(result.testFailuresCount == 0)
        #expect(result.testsPassedCount == 0)
        #expect(result.testsSkippedCount == 0)
        #expect(result.conclusion == .neutral)
    }

    @Test("Result can be created with custom values", .tags(.unit, .prReport))
    func customResult() throws {
        let result = PRReportResult(
            checkRunURL: "https://github.com/example/check/123",
            annotationsPosted: 5,
            warningsCount: 3,
            errorsCount: 2,
            testFailuresCount: 1,
            testsPassedCount: 100,
            testsSkippedCount: 5,
            conclusion: .failure
        )

        #expect(result.checkRunURL == "https://github.com/example/check/123")
        #expect(result.annotationsPosted == 5)
        #expect(result.warningsCount == 3)
        #expect(result.errorsCount == 2)
        #expect(result.testFailuresCount == 1)
        #expect(result.testsPassedCount == 100)
        #expect(result.testsSkippedCount == 5)
        #expect(result.conclusion == .failure)
    }
}

// MARK: - PRReportConclusion Tests

@Suite("PRReportConclusion Tests")
struct PRReportConclusionTests {
    @Test("Conclusion raw values are correct", .tags(.unit, .prReport))
    func conclusionRawValues() throws {
        #expect(PRReportConclusion.success.rawValue == "success")
        #expect(PRReportConclusion.failure.rawValue == "failure")
        #expect(PRReportConclusion.neutral.rawValue == "neutral")
    }
}

// MARK: - PRReportError Tests

@Suite("PRReportError Tests")
struct PRReportErrorTests {
    @Test("prReportNotEnabled error has expected message", .tags(.unit, .prReport, .errorHandling))
    func prReportNotEnabledError() throws {
        let error = PRReportError.prReportNotEnabled
        let message = error.localizedDescription
        #expect(message.contains("PR reporting is not configured"))
        #expect(message.contains("pr_report:"))
        #expect(message.contains("check_name:"))
    }

    @Test("notInGitHubActions error has expected message", .tags(.unit, .prReport, .errorHandling))
    func notInGitHubActionsError() throws {
        let error = PRReportError.notInGitHubActions
        let message = error.localizedDescription
        #expect(message.contains("GitHub Actions"))
        #expect(message.contains("GITHUB_TOKEN"))
        #expect(message.contains("GITHUB_REPOSITORY"))
        #expect(message.contains("GITHUB_SHA"))
    }

    @Test("missingGitHubToken error has expected message", .tags(.unit, .prReport, .errorHandling))
    func missingGitHubTokenError() throws {
        let error = PRReportError.missingGitHubToken
        let message = error.localizedDescription
        #expect(message.contains("GITHUB_TOKEN"))
        #expect(message.contains("secrets.GITHUB_TOKEN"))
    }

    @Test("xcresultNotFound error includes path", .tags(.unit, .prReport, .errorHandling))
    func xcresultNotFoundError() throws {
        let error = PRReportError.xcresultNotFound(path: "/path/to/result.xcresult")
        let message = error.localizedDescription
        #expect(message.contains("/path/to/result.xcresult"))
    }

    @Test("noXcresultBundles error includes directory and suggestion", .tags(.unit, .prReport, .errorHandling))
    func noXcresultBundlesError() throws {
        let error = PRReportError.noXcresultBundles(directory: "/path/to/reports")
        let message = error.localizedDescription
        #expect(message.contains("/path/to/reports"))
        #expect(message.contains("xp test") || message.contains("xp build"))
    }

    @Test("parsingFailed error includes path and reason", .tags(.unit, .prReport, .errorHandling))
    func parsingFailedError() throws {
        let error = PRReportError.parsingFailed(path: "/path/to/result.xcresult", reason: "Invalid format")
        let message = error.localizedDescription
        #expect(message.contains("/path/to/result.xcresult"))
        #expect(message.contains("Invalid format"))
    }

    @Test("reportingFailed error includes reason", .tags(.unit, .prReport, .errorHandling))
    func reportingFailedError() throws {
        let error = PRReportError.reportingFailed(reason: "API rate limit exceeded")
        let message = error.localizedDescription
        #expect(message.contains("API rate limit exceeded"))
    }

    @Test("noResultsToReport error has expected message", .tags(.unit, .prReport, .errorHandling))
    func noResultsToReportError() throws {
        let error = PRReportError.noResultsToReport
        let message = error.localizedDescription
        #expect(message.contains("No build or test results"))
    }

    @Test("forkPRDetected error has expected message", .tags(.unit, .prReport, .errorHandling))
    func forkPRDetectedError() throws {
        let error = PRReportError.forkPRDetected
        let message = error.localizedDescription
        #expect(message.contains("fork"))
        #expect(message.contains("read-only"))
    }
}

// MARK: - Integration with XprojectConfiguration Tests

@Suite("PRReport XprojectConfiguration Integration Tests")
struct PRReportXprojectConfigurationTests {
    @Test("XprojectConfiguration includes prReport field", .tags(.unit, .prReport, .configuration))
    func configurationIncludesPrReport() throws {
        let prReportConfig = PRReportConfiguration(
            checkName: "Xcode Build & Test"
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: nil,
            danger: nil,
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: prReportConfig
        )

        #expect(config.prReport != nil)
        #expect(config.prReport?.checkName == "Xcode Build & Test")
    }

    @Test("XprojectConfiguration can have nil prReport", .tags(.unit, .prReport, .configuration))
    func configurationCanHaveNilPrReport() throws {
        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: nil,
            danger: nil,
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )

        #expect(config.prReport == nil)
    }

    @Test("XprojectConfiguration decodes prReport from YAML", .tags(.unit, .prReport, .configuration))
    func configurationDecodesPrReportFromYaml() throws {
        try TestFileHelper.withTemporaryDirectory { tempDir in
            try TestFileHelper.createDummyProject(in: tempDir, name: "TestApp")

            let yaml = """
            app_name: TestApp
            project_path:
              ios: TestApp.xcodeproj
            pr_report:
              check_name: Custom Check Name
              ignore_warnings: true
              ignored_files:
                - "Pods/**"
            """

            let configURL = tempDir.appendingPathComponent("Xproject.yml")
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)

            let configService = ConfigurationService(
                workingDirectory: tempDir.path,
                customConfigPath: configURL.path
            )
            let config = try configService.configuration

            #expect(config.prReport != nil)
            #expect(config.prReport?.checkName == "Custom Check Name")
            #expect(config.prReport?.ignoreWarnings == true)
            #expect(config.prReport?.ignoredFiles == ["Pods/**"])
        }
    }
}
