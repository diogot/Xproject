//
// TestCommand.swift
// XProject
//

import ArgumentParser
import XProject

struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run project tests",
        discussion: """
            Runs unit tests for configured schemes. By default, runs all test schemes
            defined in the configuration. Supports building for testing and running
            tests on multiple destinations.

            TODO: Future enhancement - Add Danger integration support (--run-danger flag)
            """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun = false

    @Flag(name: .long, help: "Clean build before testing")
    var clean = false

    @Flag(name: .long, help: "Skip building and only run tests")
    var skipBuild = false

    @Option(
        name: .long,
        help: "Specific scheme(s) to test (can be specified multiple times)"
    )
    var scheme: [String] = []

    @Option(
        name: .long,
        help: "Override test destination for all schemes"
    )
    var destination: String?

    func run() async throws {
        let configService = ConfigurationService(customConfigPath: globalOptions.config)
        let testService = TestService(
            configurationProvider: configService,
            buildService: BuildService(
                configurationProvider: configService,
                commandExecutor: CommandExecutor(dryRun: dryRun)
            )
        )

        do {
            try await runTests(testService: testService)
        } catch {
            print("❌ Test failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func runTests(testService: TestService) async throws {
        print("🧪 Running tests...")

        printTestConfiguration()

        let results = try await testService.runTests(
            schemes: scheme.isEmpty ? nil : scheme,
            clean: clean,
            skipBuild: skipBuild,
            destination: destination
        )

        printResults(results)

        if results.hasFailures {
            throw ExitCode.failure
        }
    }

    private func printTestConfiguration() {
        if clean {
            print("🧹 Clean build enabled")
        }

        if skipBuild {
            print("⏭️  Skipping build phase")
        }

        if !scheme.isEmpty {
            print("📋 Testing schemes: \(scheme.joined(separator: ", "))")
        } else {
            print("📋 Testing all configured schemes")
        }

        if let destination = destination {
            print("📍 Using destination override: \(destination)")
        }
    }

    private func printResults(_ results: TestResults) {
        // Print detailed results for each scheme
        for (schemeName, schemeResult) in results.schemeResults.sorted(by: { $0.key < $1.key }) {
            print("\n📦 Scheme: \(schemeName)")

            printBuildResults(schemeResult)
            printTestResults(schemeResult)
        }

        // Print summary
        print("\n\(results.summary)")
    }

    private func printBuildResults(_ schemeResult: TestResults.SchemeResult) {
        if let buildSucceeded = schemeResult.buildSucceeded {
            if buildSucceeded {
                print("  ✅ Build succeeded")
            } else {
                print("  ❌ Build failed")
                if let error = schemeResult.buildError {
                    print("     \(error.localizedDescription)")
                }
            }
        }
    }

    private func printTestResults(_ schemeResult: TestResults.SchemeResult) {
        if !schemeResult.testResults.isEmpty {
            print("  🧪 Test results:")
            for testResult in schemeResult.testResults {
                if testResult.succeeded {
                    print("    ✅ \(testResult.destination)")
                } else {
                    print("    ❌ \(testResult.destination)")
                    if let error = testResult.error {
                        print("       \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
