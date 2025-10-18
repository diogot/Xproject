//
// MockXcodeClient.swift
// Xproject
//

import Foundation
@testable import Xproject

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

    public struct ReleaseCall: Sendable {
        public let environment: String
    }

    private var _buildForTestingCalls: [BuildCall] = []
    private var _runTestsCalls: [TestCall] = []
    private var _archiveCalls: [ReleaseCall] = []
    private var _generateIPACalls: [ReleaseCall] = []
    private var _uploadCalls: [ReleaseCall] = []

    private var shouldFailBuildForScheme: [String: Bool] = [:]
    private var shouldFailTestForDestination: [String: Bool] = [:]
    private var shouldFailArchiveForEnvironment: [String: Bool] = [:]
    private var shouldFailIPAForEnvironment: [String: Bool] = [:]
    private var shouldFailUploadForEnvironment: [String: Bool] = [:]

    public init() {}

    public var buildForTestingCalls: [BuildCall] {
        _buildForTestingCalls
    }

    public var runTestsCalls: [TestCall] {
        _runTestsCalls
    }

    public var archiveCalls: [ReleaseCall] {
        _archiveCalls
    }

    public var generateIPACalls: [ReleaseCall] {
        _generateIPACalls
    }

    public var uploadCalls: [ReleaseCall] {
        _uploadCalls
    }

    public func setShouldFailBuildForScheme(_ scheme: String, shouldFail: Bool) {
        shouldFailBuildForScheme[scheme] = shouldFail
    }

    public func setShouldFailTestForDestination(_ destination: String, shouldFail: Bool) {
        shouldFailTestForDestination[destination] = shouldFail
    }

    public func setShouldFailArchiveForEnvironment(_ environment: String, shouldFail: Bool) {
        shouldFailArchiveForEnvironment[environment] = shouldFail
    }

    public func setShouldFailIPAForEnvironment(_ environment: String, shouldFail: Bool) {
        shouldFailIPAForEnvironment[environment] = shouldFail
    }

    public func setShouldFailUploadForEnvironment(_ environment: String, shouldFail: Bool) {
        shouldFailUploadForEnvironment[environment] = shouldFail
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
        _archiveCalls.append(ReleaseCall(environment: environment))

        let shouldFail = shouldFailArchiveForEnvironment[environment] ?? false
        if shouldFail {
            throw XcodeClientError.configurationError("Mock archive failure for \(environment)")
        }
    }

    public func generateIPA(environment: String) async throws {
        _generateIPACalls.append(ReleaseCall(environment: environment))

        let shouldFail = shouldFailIPAForEnvironment[environment] ?? false
        if shouldFail {
            throw XcodeClientError.configurationError("Mock IPA generation failure for \(environment)")
        }
    }

    public func upload(environment: String) async throws {
        _uploadCalls.append(ReleaseCall(environment: environment))

        let shouldFail = shouldFailUploadForEnvironment[environment] ?? false
        if shouldFail {
            throw XcodeClientError.configurationError("Mock upload failure for \(environment)")
        }
    }

    public func clean() async throws {
        // Not used in tests
    }
}
