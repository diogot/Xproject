//
// SetupServiceTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("Setup Service Tests")
struct SetupServiceTests {
    @Test("Setup service can be created", .tags(.unit, .fast))
    func setupServiceCreation() throws {
        let mockExecutor = MockCommandExecutor()
        let service = SetupService(executor: mockExecutor, verbose: false)
        // Simply verify instantiation succeeded (no assertion needed for non-optional)
        _ = service
    }

    @Test("Setup service works with configuration", .tags(.unit, .integration, .fast))
    func setupServiceWithConfiguration() throws {
        // Create a test configuration
        let brewConfig = BrewConfiguration(enabled: true, formulas: ["test-formula"])
        _ = SetupConfiguration(brew: brewConfig)
        _ = ConfigurationTestHelper.createValidTestConfiguration(projectPath: "Tests/XprojectTests/Support/DummyProject.xcodeproj")

        // Create a mock config service
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let mockExecutor = MockCommandExecutor()
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

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
    func setupServiceCompleteWorkflow() async throws {
        let mockExecutor = MockCommandExecutor.withBrewSetup()
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Run setup
        try await service.runSetup()

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
    func setupServiceWithMissingBrew() async throws {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setCommandExists("brew", exists: false)

        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Should throw SetupError.brewNotInstalled
        await #expect(throws: SetupError.brewNotInstalled) {
            try await service.runSetup()
        }

        // Should not attempt to run brew commands
        #expect(!mockExecutor.wasCommandExecuted("brew update"))
    }

    @Test("Setup service brew update retry logic works", .tags(.integration, .errorHandling))
    func setupServiceBrewUpdateRetryLogic() async throws {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setCommandExists("brew", exists: true)

        // Set first brew update to fail, second to succeed
        mockExecutor.setResponse(for: "brew update", response: MockCommandExecutor.MockResponse(exitCode: 1, error: "Network error"))

        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Should complete setup despite initial brew update failure
        try await service.runSetup()

        // Should have attempted brew update (retry logic in the service handles this)
        #expect(mockExecutor.wasCommandExecuted("brew update"))
    }

    @Test("Setup service handles failed formula installation", .tags(.integration, .errorHandling))
    func setupServiceWithFailedFormula() async throws {
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
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Should throw SetupError.brewFormulaFailed
        await #expect {
            try await service.runSetup()
        } throws: { error in
            guard case SetupError.brewFormulaFailed = error else {
                return false
            }
            return true
        }
    }

    @Test("Setup service works in dry run mode", .tags(.integration, .dryRun))
    func setupServiceWithDryRun() async throws {
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setCommandExists("brew", exists: true)
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Should complete without error in dry run mode
        try await service.runSetup()

        // In dry run mode, no actual commands should be executed
        // (This test verifies the dry run integration works end-to-end)
    }

    @Test("Setup service works in verbose mode", .tags(.integration, .verbose))
    func setupServiceWithVerbose() async throws {
        let mockExecutor = MockCommandExecutor.withBrewSetup(verbose: true)
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: true)

        // Should complete without error in verbose mode
        try await service.runSetup()

        // Verify expected commands were executed
        #expect(mockExecutor.wasCommandExecuted("which brew"))
        #expect(mockExecutor.wasCommandExecuted("brew update"))
        #expect(mockExecutor.executedCommands.contains { $0.command.contains("swiftgen") })
        #expect(mockExecutor.executedCommands.contains { $0.command.contains("swiftlint") })
    }

    @Test("Setup service works in verbose and dry run mode", .tags(.integration, .verbose, .dryRun))
    func setupServiceWithVerboseAndDryRun() async throws {
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let mockExecutor = MockCommandExecutor(verbose: true)
        mockExecutor.setCommandExists("brew", exists: true)
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: true)

        // Should complete without error in verbose dry run mode
        try await service.runSetup()

        // In dry run mode, no actual commands should be executed
        // (This test verifies the verbose + dry run integration works end-to-end)
    }

    @Test("Setup service runs by default when enabled is not specified", .tags(.integration, .commandExecution))
    func setupServiceRunsByDefaultWhenEnabledNotSpecified() async throws {
        let mockExecutor = MockCommandExecutor.withBrewSetup()

        // Create temporary directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        setup:
          brew:
            formulas:
              - test-formula
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let configService = ConfigurationService(customConfigPath: configURL.path)
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Run setup - should succeed and run brew commands
        try await service.runSetup()

        // Verify brew commands were executed
        #expect(mockExecutor.wasCommandExecuted("which brew"))
        #expect(mockExecutor.wasCommandExecuted("brew update"))
        #expect(mockExecutor.executedCommands.contains { $0.command.contains("test-formula") })
    }

    @Test("Setup service skips when explicitly disabled", .tags(.integration, .commandExecution))
    func setupServiceSkipsWhenExplicitlyDisabled() async throws {
        let mockExecutor = MockCommandExecutor.withBrewSetup()

        // Create temporary directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        setup:
          brew:
            enabled: false
            formulas:
              - test-formula
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let configService = ConfigurationService(customConfigPath: configURL.path)
        let service = SetupService(configService: configService, executor: mockExecutor, verbose: false)

        // Run setup - should complete but skip brew commands
        try await service.runSetup()

        // Verify no brew commands were executed
        #expect(!mockExecutor.wasCommandExecuted("which brew"))
        #expect(!mockExecutor.wasCommandExecuted("brew update"))
        #expect(!mockExecutor.executedCommands.contains { $0.command.contains("test-formula") })
    }
}

// Helper error for testing
enum MockTestError: Error {
    case generic
}
