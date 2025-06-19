//
// TestService.swift
// XProject
//

import Foundation

// MARK: - Test Service Protocol

public protocol TestServiceProtocol: Sendable {
    func runTests(
        schemes: [String]?,
        clean: Bool,
        skipBuild: Bool,
        destination: String?
    ) async throws -> TestResults
}

// MARK: - Test Service

public final class TestService: TestServiceProtocol, Sendable {
    private let configurationProvider: any ConfigurationProviding
    private let xcodeClient: any XcodeClientProtocol

    public init(
        configurationProvider: any ConfigurationProviding = ConfigurationService.shared,
        xcodeClient: (any XcodeClientProtocol)? = nil
    ) {
        self.configurationProvider = configurationProvider
        self.xcodeClient = xcodeClient ?? XcodeClient(
            configurationProvider: configurationProvider
        )
    }

    // MARK: - Public Methods

    public func runTests(
        schemes: [String]? = nil,
        clean: Bool = false,
        skipBuild: Bool = false,
        destination: String? = nil
    ) async throws -> TestResults {
        let config = try configurationProvider.configuration
        let configFilePath = try configurationProvider.configurationFilePath

        guard let xcodeConfig = config.xcode else {
            throw TestError.noXcodeConfiguration(configFile: configFilePath)
        }

        guard let testsConfig = xcodeConfig.tests else {
            throw TestError.noTestConfiguration(configFile: configFilePath)
        }

        let schemesToTest = try resolveSchemesToTest(
            schemes: schemes,
            testsConfig: testsConfig
        )

        var results = TestResults()

        for schemeConfig in schemesToTest {
            let schemeResults = try await runTestsForScheme(
                schemeConfig: schemeConfig,
                clean: clean,
                skipBuild: skipBuild,
                overrideDestination: destination
            )
            results.merge(with: schemeResults)
        }

        return results
    }

    // MARK: - Private Methods

    private func resolveSchemesToTest(
        schemes: [String]?,
        testsConfig: TestsConfiguration
    ) throws -> [TestSchemeConfiguration] {
        guard let schemes = schemes, !schemes.isEmpty else {
            // No specific schemes requested, test all
            return testsConfig.schemes
        }

        // Filter to requested schemes
        let schemesToTest = testsConfig.schemes.filter { schemeConfig in
            schemes.contains(schemeConfig.scheme)
        }

        // Verify all requested schemes were found
        let foundSchemes = Set(schemesToTest.map { $0.scheme })
        let requestedSchemes = Set(schemes)
        let missingSchemes = requestedSchemes.subtracting(foundSchemes)

        if !missingSchemes.isEmpty {
            throw TestError.schemesNotFound(Array(missingSchemes))
        }

        return schemesToTest
    }

    private func runTestsForScheme(
        schemeConfig: TestSchemeConfiguration,
        clean: Bool,
        skipBuild: Bool,
        overrideDestination: String?
    ) async throws -> TestResults {
        var results = TestResults()

        // Build for testing (unless skipping)
        if !skipBuild {
            do {
                try await xcodeClient.buildForTesting(
                    scheme: schemeConfig.scheme,
                    clean: clean,
                    buildDestination: schemeConfig.buildDestination
                )
                results.recordBuildSuccess(scheme: schemeConfig.scheme)
            } catch {
                results.recordBuildFailure(
                    scheme: schemeConfig.scheme,
                    error: error
                )
                // Can't run tests if build failed
                return results
            }
        }

        // Determine test destinations
        let destinations: [String]
        if let overrideDestination = overrideDestination {
            destinations = [overrideDestination]
        } else {
            destinations = schemeConfig.testDestinations
        }

        // Run tests on each destination
        for destination in destinations {
            do {
                try await xcodeClient.runTests(
                    scheme: schemeConfig.scheme,
                    destination: destination
                )
                results.recordTestSuccess(
                    scheme: schemeConfig.scheme,
                    destination: destination
                )
            } catch {
                results.recordTestFailure(
                    scheme: schemeConfig.scheme,
                    destination: destination,
                    error: error
                )
            }
        }

        return results
    }
}

// MARK: - Test Results

public struct TestResults: Sendable {
    public struct SchemeResult: Sendable {
        public let scheme: String
        public var buildSucceeded: Bool?
        public var buildError: Error?
        public var testResults: [DestinationResult] = []

        public var hasFailures: Bool {
            if buildSucceeded == false {
                return true
            }
            return testResults.contains { !$0.succeeded }
        }
    }

    public struct DestinationResult: Sendable {
        public let destination: String
        public let succeeded: Bool
        public let error: Error?
    }

    public private(set) var schemeResults: [String: SchemeResult] = [:]

    public var totalSchemes: Int {
        schemeResults.count
    }

    public var failedSchemes: Int {
        schemeResults.values.filter { $0.hasFailures }.count
    }

    public var hasFailures: Bool {
        failedSchemes > 0
    }

    public var summary: String {
        if hasFailures {
            return "❌ Tests failed: \(failedSchemes) of \(totalSchemes) schemes had failures"
        } else {
            return "✅ All tests passed: \(totalSchemes) schemes tested successfully"
        }
    }

    mutating func recordBuildSuccess(scheme: String) {
        var result = schemeResults[scheme] ?? SchemeResult(scheme: scheme)
        result.buildSucceeded = true
        result.buildError = nil
        schemeResults[scheme] = result
    }

    mutating func recordBuildFailure(scheme: String, error: Error) {
        var result = schemeResults[scheme] ?? SchemeResult(scheme: scheme)
        result.buildSucceeded = false
        result.buildError = error
        schemeResults[scheme] = result
    }

    mutating func recordTestSuccess(scheme: String, destination: String) {
        var result = schemeResults[scheme] ?? SchemeResult(scheme: scheme)
        let destinationResult = DestinationResult(
            destination: destination,
            succeeded: true,
            error: nil
        )
        result.testResults.append(destinationResult)
        schemeResults[scheme] = result
    }

    mutating func recordTestFailure(scheme: String, destination: String, error: Error) {
        var result = schemeResults[scheme] ?? SchemeResult(scheme: scheme)
        let destinationResult = DestinationResult(
            destination: destination,
            succeeded: false,
            error: error
        )
        result.testResults.append(destinationResult)
        schemeResults[scheme] = result
    }

    mutating func merge(with other: TestResults) {
        for (scheme, result) in other.schemeResults {
            schemeResults[scheme] = result
        }
    }
}

// MARK: - Test Errors

public enum TestError: Error, LocalizedError, Sendable {
    case noTestConfiguration(configFile: String?)
    case noXcodeConfiguration(configFile: String?)
    case schemesNotFound([String])
    case buildFailed(scheme: String, error: Error)
    case testsFailed(failures: [(scheme: String, destination: String, error: Error)])

    public var errorDescription: String? {
        switch self {
        case .noTestConfiguration(let configFile):
            let fileInfo = configFile.map { " (loaded from \($0))" } ?? ""
            return "No test configuration found in xcode.tests\(fileInfo). Add a 'tests' section under 'xcode' in your configuration file."
        case .noXcodeConfiguration(let configFile):
            let fileInfo = configFile.map { " (loaded from \($0))" } ?? ""
            return "No xcode configuration found\(fileInfo). Add an 'xcode' section to your configuration file."
        case .schemesNotFound(let schemes):
            return "Schemes not found in configuration: \(schemes.joined(separator: ", "))"
        case let .buildFailed(scheme, error):
            return "Build failed for scheme '\(scheme)': \(error.localizedDescription)"
        case .testsFailed(let failures):
            let failureDescriptions = failures.map { scheme, destination, error in
                "\(scheme) on \(destination): \(error.localizedDescription)"
            }
            return "Tests failed:\n\(failureDescriptions.joined(separator: "\n"))"
        }
    }
}
