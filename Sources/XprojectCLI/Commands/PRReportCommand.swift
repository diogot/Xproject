//
// PRReportCommand.swift
// Xproject
//
// Command for posting build/test results to GitHub PRs
//

import ArgumentParser
import Foundation
import Xproject

struct PRReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-report",
        abstract: "Post build/test results to GitHub PR",
        discussion: """
            Posts build warnings, errors, and test failures to GitHub PRs via the
            Checks API. Requires running in a GitHub Actions environment with
            GITHUB_TOKEN set.

            By default, discovers all .xcresult bundles in the reports directory.
            Use --xcresult to specify explicit paths.

            Examples:
              xp pr-report
              xp pr-report --check-name "iOS Tests"
              xp pr-report --xcresult reports/test.xcresult
              xp pr-report --build-only --dry-run
            """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Option(
        name: .long,
        help: "Path to xcresult bundle (can specify multiple). If omitted, discovers all .xcresult in reports directory."
    )
    var xcresult: [String] = []

    @Option(
        name: .long,
        help: "Name for the GitHub Check Run"
    )
    var checkName: String?

    @Flag(
        name: .long,
        help: "Report only build results (warnings/errors)"
    )
    var buildOnly = false

    @Flag(
        name: .long,
        help: "Report only test results (failures)"
    )
    var testOnly = false

    @Flag(
        name: .long,
        help: "Show what would be reported without posting to GitHub"
    )
    var dryRun = false

    func run() async throws {
        let workingDirectory = globalOptions.resolvedWorkingDirectory

        // Print info block at start
        OutputFormatter.printInfoBlock(
            workingDirectory: workingDirectory,
            configFile: globalOptions.config,
            verbose: globalOptions.verbose
        )

        let configService = ConfigurationService(
            workingDirectory: workingDirectory,
            customConfigPath: globalOptions.config
        )

        do {
            let config = try configService.configuration

            // Get PR report configuration (section must exist)
            guard let prReportConfig = config.prReport else {
                throw PRReportError.prReportNotEnabled
            }

            let reportsPath = config.xcode?.reportsPath ?? "reports"

            let service = PRReportService(
                workingDirectory: workingDirectory,
                config: prReportConfig,
                reportsPath: reportsPath
            )

            try await reportResults(service: service)
        } catch let error as PRReportError {
            print("❌ PR report failed: \(error.localizedDescription)")
            throw ExitCode.failure
        } catch {
            print("❌ PR report failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func reportResults(service: PRReportService) async throws {
        print("📊 Reporting build/test results to GitHub PR...")

        if dryRun {
            print("🔍 Dry-run mode: showing what would be reported")
        }

        // Show what we're going to process
        if xcresult.isEmpty {
            let discovered = try service.discoverXcresultBundles()
            if discovered.isEmpty {
                throw PRReportError.noXcresultBundles(directory: service.reportsPath)
            }
            print("📦 Discovered \(discovered.count) xcresult bundle\(discovered.count == 1 ? "" : "s"):")
            for path in discovered {
                let filename = (path as NSString).lastPathComponent
                print("   - \(filename)")
            }
        } else {
            print("📦 Processing \(xcresult.count) xcresult bundle\(xcresult.count == 1 ? "" : "s"):")
            for path in xcresult {
                print("   - \(path)")
            }
        }

        if buildOnly {
            print("📋 Reporting build results only")
        } else if testOnly {
            print("📋 Reporting test results only")
        }

        let result = try await service.report(
            xcresultPaths: xcresult,
            checkName: checkName,
            buildOnly: buildOnly,
            testOnly: testOnly,
            dryRun: dryRun
        )

        printResults(result)

        // Exit with failure if there are errors
        if result.conclusion == .failure {
            throw ExitCode.failure
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func printResults(_ result: PRReportResult) {
        print("")
        print("📈 Results:")

        // Build stats
        if result.errorsCount > 0 || result.warningsCount > 0 {
            if result.errorsCount > 0 {
                print("   ❌ \(result.errorsCount) error\(result.errorsCount == 1 ? "" : "s")")
            }
            if result.warningsCount > 0 {
                print("   ⚠️  \(result.warningsCount) warning\(result.warningsCount == 1 ? "" : "s")")
            }
        }

        // Test stats
        let totalTests = result.testsPassedCount + result.testFailuresCount + result.testsSkippedCount
        if totalTests > 0 {
            if result.testFailuresCount > 0 {
                print("   ❌ \(result.testFailuresCount) test\(result.testFailuresCount == 1 ? "" : "s") failed")
            }
            print("   ✅ \(result.testsPassedCount) test\(result.testsPassedCount == 1 ? "" : "s") passed")
            if result.testsSkippedCount > 0 {
                print("   ⏭️  \(result.testsSkippedCount) test\(result.testsSkippedCount == 1 ? "" : "s") skipped")
            }
        }

        // Annotation count
        print("   📝 \(result.annotationsPosted) annotation\(result.annotationsPosted == 1 ? "" : "s") posted")

        // Conclusion
        let conclusionEmoji: String
        let conclusionText: String
        switch result.conclusion {
        case .success:
            conclusionEmoji = "✅"
            conclusionText = "Success"
        case .failure:
            conclusionEmoji = "❌"
            conclusionText = "Failure"
        case .neutral:
            conclusionEmoji = "⚪"
            conclusionText = "Neutral"
        }
        print("   \(conclusionEmoji) Conclusion: \(conclusionText)")

        // Check run URL
        if let url = result.checkRunURL {
            print("")
            print("🔗 Check run: \(url)")
        }

        // Final status
        print("")
        if dryRun {
            // Explicit dry-run mode
            printDryRunDetails(result)
            if let skipReason = result.skipReason {
                // Also show context issue for informational purposes
                print("ℹ️  Note: GitHub posting would have been skipped anyway: \(skipReason)")
            }
            print("✅ Dry-run complete (no changes made)")
        } else if let skipReason = result.skipReason {
            // GitHub posting was skipped due to context issues (not explicit dry-run)
            printDryRunDetails(result)
            print("⚠️  GitHub posting skipped: \(skipReason)")
            print("   Results displayed above (no changes made)")
        } else {
            print("✅ PR report complete")
        }
    }

    private func printDryRunDetails(_ result: PRReportResult) {
        // Print summary that would be posted
        if let summary = result.summary {
            print("📋 Summary that would be posted:")
            print("─────────────────────────────────")
            print(summary)
            print("─────────────────────────────────")
            print("")
        }

        // Print annotations that would be posted
        if let annotations = result.annotations, !annotations.isEmpty {
            print("📌 Annotations that would be posted:")
            print("")
            for annotation in annotations {
                let levelEmoji: String
                switch annotation.level {
                case .failure:
                    levelEmoji = "❌"
                case .warning:
                    levelEmoji = "⚠️"
                case .notice:
                    levelEmoji = "ℹ️"
                }
                let location = annotation.column.map { "\(annotation.path):\(annotation.line):\($0)" }
                    ?? "\(annotation.path):\(annotation.line)"
                let title = annotation.title.map { "[\($0)] " } ?? ""
                print("   \(levelEmoji) \(location)")
                print("      \(title)\(annotation.message)")
                print("")
            }
        }
    }
}
