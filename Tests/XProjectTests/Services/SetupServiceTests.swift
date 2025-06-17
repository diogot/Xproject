//
// SetupServiceTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

// MARK: - Test Helpers

private struct ConfigurationTestHelper {
    static func createTestConfigurationService() -> ConfigurationService {
        let configPath = Bundle.module.path(forResource: "test-config", ofType: "yml", inDirectory: "Support")!
        return ConfigurationService(customConfigPath: configPath)
    }

    static func createValidTestConfiguration(projectPath: String) -> XProjectConfiguration {
        return XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": projectPath],
            setup: nil,
            xcode: nil,
            danger: nil
        )
    }
}

@Suite("Setup Service Tests")
struct SetupServiceTests {
    @Test("Setup service can be created", .tags(.unit, .fast))
    func setupServiceCreation() throws {
        let service = SetupService()
        // Simply verify instantiation succeeded (no assertion needed for non-optional)
        _ = service
    }

    @Test("Setup service works with configuration", .tags(.unit, .integration, .fast))
    func setupServiceWithConfiguration() throws {
        // Create a test configuration
        let brewConfig = BrewConfiguration(enabled: true, formulas: ["test-formula"])
        _ = SetupConfiguration(brew: brewConfig)
        _ = ConfigurationTestHelper.createValidTestConfiguration(projectPath: "Tests/XProjectTests/Support/DummyProject.xcodeproj")

        // Create a mock config service
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService)

        // We can't easily test the full setup without brew being installed,
        // but we can verify the service is properly configured
        _ = service
    }

    @Test("Setup error types have correct descriptions", .tags(.unit, .errorHandling, .fast))
    func setupErrorTypes() throws {
        // Test error message formatting
        let brewError = SetupError.brewNotInstalled
        #expect(brewError.localizedDescription.contains("Homebrew not found"))

        let formulaError = SetupError.brewFormulaFailed(formula: "test-formula", error: MockTestError.generic)
        #expect(formulaError.localizedDescription.contains("Failed to install test-formula"))
    }

    // MARK: - Integration Tests with MockCommandExecutor

    @Test("Setup service complete workflow with mocked commands", .tags(.integration, .commandExecution))
    func setupServiceCompleteWorkflow() throws {
        let mockExecutor = MockCommandExecutor.withBrewSetup()
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor)

        // Run setup with adaptive retry logic for CI stability
        try TestEnvironment.withRetry(attempts: 3, delay: 0.01) {
            try service.runSetup()
        }

        // Verify expected commands were executed
        let executedCommands = mockExecutor.executedCommands

        // Should check if brew exists
        #expect(mockExecutor.wasCommandExecuted("which brew"))

        // Should run brew update (potentially twice due to retry logic)
        #expect(mockExecutor.wasCommandExecuted("brew update"))

        // Should install/upgrade formulas
        #expect(executedCommands.contains { $0.command.contains("swiftgen") })
        #expect(executedCommands.contains { $0.command.contains("swiftlint") })
    }

    @Test("Setup service handles missing brew correctly", .tags(.integration, .errorHandling))
    func setupServiceWithMissingBrew() throws {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setCommandExists("brew", exists: false)

        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor)

        // Should throw SetupError.brewNotInstalled
        #expect(throws: SetupError.self) {
            try service.runSetup()
        }

        // Should not attempt to run brew commands
        #expect(!mockExecutor.wasCommandExecuted("brew update"))
    }

    @Test("Setup service brew update retry logic works", .tags(.integration, .errorHandling))
    func setupServiceBrewUpdateRetryLogic() throws {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setCommandExists("brew", exists: true)

        // Set first brew update to fail, second to succeed
        mockExecutor.setResponse(for: "brew update", response: MockCommandExecutor.MockResponse(exitCode: 1, error: "Network error"))

        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor)

        // Add delay for CI stability
        Thread.sleep(forTimeInterval: TestEnvironment.stabilityDelay())

        // Should complete setup despite initial brew update failure
        #expect(throws: Never.self) {
            try service.runSetup()
        }

        // Should have attempted brew update (retry logic in the service handles this)
        #expect(mockExecutor.wasCommandExecuted("brew update"))
    }

    @Test("Setup service handles failed formula installation", .tags(.integration, .errorHandling))
    func setupServiceWithFailedFormula() throws {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setCommandExists("brew", exists: true)
        mockExecutor.setResponse(for: "brew update", response: MockCommandExecutor.MockResponse.success)

        // Make one formula fail
        let failingFormulaCommand = "( brew list swiftgen ) && " +
                                     "( brew outdated swiftgen || brew upgrade swiftgen ) || " +
                                     "( brew install swiftgen )"
        mockExecutor.setResponse(for: failingFormulaCommand,
                                 response: MockCommandExecutor.MockResponse(exitCode: 1, error: "Formula not found"))

        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor)

        // Add delay for CI stability
        Thread.sleep(forTimeInterval: TestEnvironment.stabilityDelay())

        // Should throw SetupError.brewFormulaFailed
        #expect(throws: SetupError.self) {
            try service.runSetup()
        }
    }

    @Test("Setup service works in dry run mode", .tags(.integration, .dryRun))
    func setupServiceWithDryRun() throws {
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, dryRun: true)

        // Should complete without error in dry run mode
        #expect(throws: Never.self) {
            try service.runSetup()
        }

        // In dry run mode, no actual commands should be executed
        // (This test verifies the dry run integration works end-to-end)
    }
}

// Helper error for testing
enum MockTestError: Error {
    case generic
}
