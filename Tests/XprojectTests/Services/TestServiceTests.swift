//
// TestServiceTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("TestService Tests", .tags(.testService))
struct TestServiceTests {
    @Test("TestService can be instantiated")
    func testServiceInstantiation() throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let mockConfigProvider = MockConfigurationProvider(
            config: createTestConfiguration()
        )

        // When
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // Then
        #expect(type(of: testService) == TestService.self)
    }

    @Test("TestService runs all schemes when none specified")
    func testRunAllSchemes() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await testService.runTests()

        // Then
        #expect(results.totalSchemes == 2)
        #expect(await mockXcodeClient.buildForTestingCalls.count == 2)
        #expect(await mockXcodeClient.runTestsCalls.count == 3) // 2 destinations for Nebula, 1 for NebulaTV
    }

    @Test("TestService runs specific scheme when requested")
    func testRunSpecificScheme() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await testService.runTests(schemes: ["Nebula"])

        // Then
        #expect(results.totalSchemes == 1)
        let buildCalls = await mockXcodeClient.buildForTestingCalls
        #expect(buildCalls.count == 1)
        #expect(buildCalls[0].scheme == "Nebula")
        #expect(await mockXcodeClient.runTestsCalls.count == 2) // 2 destinations for Nebula
    }

    @Test("TestService throws error for unknown scheme")
    func testUnknownSchemeError() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When/Then
        do {
            _ = try await testService.runTests(schemes: ["UnknownScheme"])
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as TestError {
            switch error {
            case .schemesNotFound(let schemes):
                #expect(schemes == ["UnknownScheme"])
            default:
                #expect(Bool(false), "Wrong TestError type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("TestService skips build when requested")
    func testSkipBuild() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        _ = try await testService.runTests(skipBuild: true)

        // Then
        #expect(await mockXcodeClient.buildForTestingCalls.isEmpty)
        let testCalls = await mockXcodeClient.runTestsCalls
        #expect(!testCalls.isEmpty)
    }

    @Test("TestService uses clean build when requested")
    func testCleanBuild() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        _ = try await testService.runTests(clean: true)

        // Then
        let buildCalls = await mockXcodeClient.buildForTestingCalls
        #expect(buildCalls.allSatisfy { $0.clean == true })
    }

    @Test("TestService uses destination override")
    func testDestinationOverride() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )
        let overrideDestination = "platform=iOS Simulator,OS=17.0,name=iPhone 15"

        // When
        _ = try await testService.runTests(destination: overrideDestination)

        // Then
        let testCalls = await mockXcodeClient.runTestsCalls
        #expect(testCalls.allSatisfy { $0.destination == overrideDestination })
    }

    @Test("TestService aggregates build failures")
    func testBuildFailureAggregation() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        await mockXcodeClient.setShouldFailBuildForScheme("Nebula", shouldFail: true)
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await testService.runTests()

        // Then
        #expect(results.hasFailures)
        #expect(results.failedSchemes == 1)
        let nebulaResult = results.schemeResults["Nebula"]
        #expect(nebulaResult?.buildSucceeded == false)
        #expect(nebulaResult?.testResults.isEmpty == true) // No tests run if build failed
    }

    @Test("TestService aggregates test failures")
    func testTestFailureAggregation() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let failingDestination = "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro"
        await mockXcodeClient.setShouldFailTestForDestination(failingDestination, shouldFail: true)
        let config = createTestConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await testService.runTests()

        // Then
        #expect(results.hasFailures)
        let nebulaResult = results.schemeResults["Nebula"]
        #expect(nebulaResult?.testResults.count == 2)
        let failedTest = nebulaResult?.testResults.first { $0.destination == failingDestination }
        #expect(failedTest?.succeeded == false)
    }

    @Test("TestService handles missing test configuration")
    func testMissingTestConfiguration() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: nil,
                reportsPath: nil,
                tests: nil,  // No test configuration
                release: nil
            ),
            danger: nil
        )
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let testService = TestService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When/Then
        do {
            _ = try await testService.runTests()
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as TestError {
            switch error {
            case .noTestConfiguration, .noXcodeConfiguration:
                // Expected error
                break
            default:
                #expect(Bool(false), "Wrong TestError type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("TestResults summary messages are correct")
    func testResultsSummaryMessages() throws {
        // Given - all passing
        var results = TestResults()
        results.recordBuildSuccess(scheme: "Scheme1")
        results.recordTestSuccess(scheme: "Scheme1", destination: "Dest1")
        results.recordBuildSuccess(scheme: "Scheme2")
        results.recordTestSuccess(scheme: "Scheme2", destination: "Dest2")

        // Then
        #expect(results.summary.contains("All tests passed"))
        #expect(!results.hasFailures)

        // Given - with failures
        results.recordBuildFailure(scheme: "Scheme3", error: XcodeClientError.configurationError("Test error"))

        // Then
        #expect(results.summary.contains("Tests failed"))
        #expect(results.hasFailures)
        #expect(results.failedSchemes == 1)
    }
}

private func createTestConfiguration() -> XprojectConfiguration {
    return ConfigurationTestHelper.createTestConfigurationWithXcode()
}
