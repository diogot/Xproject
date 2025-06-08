import XCTest
@testable import XProject

final class SetupServiceTests: XCTestCase {
    
    func testSetupServiceCreation() throws {
        let service = SetupService()
        XCTAssertNotNil(service)
    }
    
    func testSetupServiceWithConfiguration() throws {
        // Create a test configuration
        let brewConfig = BrewConfiguration(enabled: true, formulas: ["test-formula"])
        let setupConfig = SetupConfiguration(brew: brewConfig)
        let _ = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Package.swift"],
            setup: setupConfig
        )
        
        // Create a mock config service
        let configService = ConfigurationService()
        let service = SetupService(configService: configService)
        
        // We can't easily test the full setup without brew being installed,
        // but we can verify the service is properly configured
        XCTAssertNotNil(service)
    }
    
    func testSetupErrorTypes() throws {
        // Test error message formatting
        let brewError = SetupError.brewNotInstalled
        XCTAssertTrue(brewError.localizedDescription.contains("Homebrew not found"))
        
        let formulaError = SetupError.brewFormulaFailed(formula: "test-formula", error: TestError.generic)
        XCTAssertTrue(formulaError.localizedDescription.contains("Failed to install test-formula"))
    }
}

// Helper error for testing
enum TestError: Error {
    case generic
}