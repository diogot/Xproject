//
// ConfigurationServiceTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

@Suite("ConfigurationService Tests")
struct ConfigurationServiceTests {
    // MARK: - ConfigurationService Thread Safety Tests

    @Test("Configuration service handles concurrent access safely", .tags(.threading, .configuration, .integration))
    func configurationServiceThreadSafety() async throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Test concurrent access to configuration
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try service.configuration
                }
            }
            // Automatically waits for all tasks to complete
        }
    }

    @Test("Configuration service handles concurrent reload operations", .tags(.threading, .configuration, .integration))
    func configurationServiceConcurrentReload() async throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Load initial configuration
        _ = try service.configuration

        // Test concurrent reload operations
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try service.reload()
                }
            }
            // Automatically waits for all tasks to complete
        }
    }

    @Test("Configuration service cache remains consistent", .tags(.configuration, .unit))
    func configurationServiceCacheConsistency() throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Load configuration multiple times and ensure it's consistent
        let config1 = try service.configuration
        let config2 = try service.configuration
        let config3 = try service.configuration

        #expect(config1.appName == config2.appName)
        #expect(config2.appName == config3.appName)
        #expect(config1.projectPaths.count == config2.projectPaths.count)
        #expect(config2.projectPaths.count == config3.projectPaths.count)
    }

    @Test("Configuration service cache can be cleared", .tags(.configuration, .unit))
    func configurationServiceClearCache() throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Load configuration
        _ = try service.configuration
        #expect(service.isLoaded)

        // Clear cache
        service.clearCache()
        #expect(!service.isLoaded)

        // Should be able to load again
        _ = try service.configuration
        #expect(service.isLoaded)
    }

    @Test("Configuration service convenience methods work correctly", .tags(.configuration, .integration))
    func configurationServiceConvenienceMethods() throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Test convenience methods
        let appName = try service.appName
        #expect(appName == "XProject")

        let projectPaths = try service.projectPaths
        #expect(projectPaths["cli"] == "DummyProject.xcodeproj")

        let projectPath = try service.projectPath(for: "cli")
        #expect(projectPath == "DummyProject.xcodeproj")

        let isBrewEnabled = try service.isEnabled("setup.brew")
        #expect(isBrewEnabled)

        let setup = try service.setup
        #expect(setup != nil)
        #expect(setup?.brew != nil)
    }

    @Test("Configuration service path resolution works correctly", .tags(.configuration, .fileSystem, .unit))
    func configurationServicePathResolution() throws {
        let service = ConfigurationTestHelper.createTestConfigurationService()

        // Test path resolution
        let relativePath = service.resolvePath("test/path")
        #expect(relativePath.path.hasPrefix("/")) // Should be absolute path
        #expect(relativePath.path.hasSuffix("test/path"))

        let absolutePath = service.resolvePath("/absolute/path")
        #expect(absolutePath.path == "/absolute/path")

        // Test project URL generation
        let projectURL = try service.projectURL(for: "cli")
        #expect(projectURL != nil)
        #expect(projectURL!.path.hasSuffix("DummyProject.xcodeproj"))

        // Test build and reports paths
        let buildPath = service.buildPath()
        #expect(buildPath.path.hasSuffix("build"))

        let reportsPath = service.reportsPath()
        #expect(reportsPath.path.hasSuffix("reports"))
    }
}
