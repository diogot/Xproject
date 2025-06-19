//
// XprojectTests.swift
// Xproject
//

import Testing
@testable import Xproject

@Suite("Xproject Core Tests")
struct XprojectTests {
    @Test("Xproject version is correct", .tags(.unit, .fast))
    func version() throws {
        #expect(Xproject.version == "0.1.0")
    }

    @Test("Xproject can be instantiated", .tags(.unit, .fast))
    func instantiation() throws {
        let core = Xproject()
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
