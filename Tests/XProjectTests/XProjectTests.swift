import XCTest
@testable import XProject

final class XProjectTests: XCTestCase {
    
    func testVersion() throws {
        XCTAssertEqual(XProject.version, "0.1.0")
    }
    
    func testXProjectCanBeInstantiated() throws {
        let core = XProject()
        XCTAssertNotNil(core)
    }
    
    func testConfigurationServiceIsAvailable() throws {
        // Test that we can access the configuration service
        let service = ConfigurationService.shared
        XCTAssertNotNil(service)
    }
}