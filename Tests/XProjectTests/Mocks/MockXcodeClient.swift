//
// MockXcodeClient.swift
// XProject
//

import Foundation
@testable import XProject

/// Mock implementation of XcodeClientProtocol for testing
public actor MockXcodeClient: XcodeClientProtocol {
    public struct BuildCall: Sendable {
        public let scheme: String
        public let clean: Bool
        public let buildDestination: String
    }

    public struct TestCall: Sendable {
        public let scheme: String
        public let destination: String
    }

    private var _buildForTestingCalls: [BuildCall] = []
    private var _runTestsCalls: [TestCall] = []

    private var shouldFailBuildForScheme: [String: Bool] = [:]
    private var shouldFailTestForDestination: [String: Bool] = [:]

    public init() {}

    public var buildForTestingCalls: [BuildCall] {
        _buildForTestingCalls
    }

    public var runTestsCalls: [TestCall] {
        _runTestsCalls
    }

    public func setShouldFailBuildForScheme(_ scheme: String, shouldFail: Bool) {
        shouldFailBuildForScheme[scheme] = shouldFail
    }

    public func setShouldFailTestForDestination(_ destination: String, shouldFail: Bool) {
        shouldFailTestForDestination[destination] = shouldFail
    }

    public func buildForTesting(scheme: String, clean: Bool, buildDestination: String) async throws {
        _buildForTestingCalls.append(BuildCall(
            scheme: scheme,
            clean: clean,
            buildDestination: buildDestination
        ))

        let shouldFail = shouldFailBuildForScheme[scheme] ?? false
        if shouldFail {
            throw XcodeClientError.configurationError("Mock build failure for \(scheme)")
        }
    }

    public func runTests(scheme: String, destination: String) async throws {
        _runTestsCalls.append(TestCall(scheme: scheme, destination: destination))

        let shouldFail = shouldFailTestForDestination[destination] ?? false
        if shouldFail {
            throw XcodeClientError.configurationError("Mock test failure for \(destination)")
        }
    }

    public func archive(environment: String) async throws {
        // Not used in tests
    }

    public func generateIPA(environment: String) async throws {
        // Not used in tests
    }

    public func upload(environment: String) async throws {
        // Not used in tests
    }

    public func clean() async throws {
        // Not used in tests
    }
}
