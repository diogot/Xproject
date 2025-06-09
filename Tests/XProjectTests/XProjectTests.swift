import Testing
@testable import XProject

@Suite("XProject Core Tests")
struct XProjectTests {

    @Test("XProject version is correct", .tags(.unit, .fast))
    func version() throws {
        #expect(XProject.version == "0.1.0")
    }

    @Test("XProject can be instantiated", .tags(.unit, .fast))
    func instantiation() throws {
        let core = XProject()
        // Simply verify instantiation succeeded (no assertion needed for non-optional)
        _ = core
    }

    @Test("Configuration service is available", .tags(.unit, .fast))
    func configurationServiceAvailability() throws {
        // Test that we can access the configuration service
        let service = ConfigurationService.shared
        // Simply verify access succeeded (no assertion needed for non-optional)
        _ = service
    }
}
