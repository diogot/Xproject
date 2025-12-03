//
// CleanServiceTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

/// Mock file system for testing CleanService
final class MockFileSystemOperator: FileSystemOperating, @unchecked Sendable {
    private var existingPaths: Set<String> = []
    private var removedPaths: [String] = []
    private var shouldFailRemoval: [String: Error] = [:]

    func setExists(_ path: String) {
        existingPaths.insert(path)
    }

    func setFailsRemoval(_ path: String, error: Error) {
        shouldFailRemoval[path] = error
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func removeItem(atPath path: String) throws {
        if let error = shouldFailRemoval[path] {
            throw error
        }
        existingPaths.remove(path)
        removedPaths.append(path)
    }

    func wasRemoved(_ path: String) -> Bool {
        removedPaths.contains(path)
    }

    var allRemovedPaths: [String] {
        removedPaths
    }
}

@Suite("Clean Service Tests")
struct CleanServiceTests {
    // MARK: - Basic Tests

    @Test("Clean service can be created", .tags(.unit, .fast))
    func cleanServiceCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory.path
        let configService = ConfigurationTestHelper.createTestConfigurationService()
        let service = CleanService(
            workingDirectory: tempDir,
            configurationProvider: configService
        )
        _ = service
    }

    @Test("Clean result reports nothing to clean when no directories exist", .tags(.unit, .fast))
    func cleanResultNothingToClean() throws {
        let result = CleanResult(
            buildPath: "build",
            reportsPath: "reports",
            buildRemoved: false,
            reportsRemoved: false
        )
        #expect(result.nothingToClean == true)
    }

    @Test("Clean result reports something cleaned when directories removed", .tags(.unit, .fast))
    func cleanResultSomethingCleaned() throws {
        let result = CleanResult(
            buildPath: "build",
            reportsPath: "reports",
            buildRemoved: true,
            reportsRemoved: false
        )
        #expect(result.nothingToClean == false)
    }

    // MARK: - Integration Tests with Mock File System

    @Test("Clean removes existing build and reports directories", .tags(.integration))
    func cleanRemovesExistingDirectories() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
          build_path: build
          reports_path: reports
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let buildPath = tempDir.appendingPathComponent("build").path
        let reportsPath = tempDir.appendingPathComponent("reports").path

        let mockFileSystem = MockFileSystemOperator()
        mockFileSystem.setExists(buildPath)
        mockFileSystem.setExists(reportsPath)

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        let result = try service.clean(dryRun: false)

        #expect(result.buildRemoved == true)
        #expect(result.reportsRemoved == true)
        #expect(mockFileSystem.wasRemoved(buildPath))
        #expect(mockFileSystem.wasRemoved(reportsPath))
    }

    @Test("Clean reports nothing to clean when directories don't exist", .tags(.integration))
    func cleanReportsNothingWhenDirectoriesMissing() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let mockFileSystem = MockFileSystemOperator()
        // Don't set any paths as existing

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        let result = try service.clean(dryRun: false)

        #expect(result.nothingToClean == true)
        #expect(result.buildRemoved == false)
        #expect(result.reportsRemoved == false)
        #expect(mockFileSystem.allRemovedPaths.isEmpty)
    }

    @Test("Clean dry run doesn't actually remove directories", .tags(.integration, .dryRun))
    func cleanDryRunDoesNotRemove() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let buildPath = tempDir.appendingPathComponent("build").path
        let reportsPath = tempDir.appendingPathComponent("reports").path

        let mockFileSystem = MockFileSystemOperator()
        mockFileSystem.setExists(buildPath)
        mockFileSystem.setExists(reportsPath)

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        let result = try service.clean(dryRun: true)

        // Should report what would be cleaned
        #expect(result.buildRemoved == true)
        #expect(result.reportsRemoved == true)

        // But shouldn't actually remove anything
        #expect(mockFileSystem.allRemovedPaths.isEmpty)
    }

    @Test("Clean only removes build directory when reports doesn't exist", .tags(.integration))
    func cleanOnlyBuildWhenReportsMissing() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let buildPath = tempDir.appendingPathComponent("build").path

        let mockFileSystem = MockFileSystemOperator()
        mockFileSystem.setExists(buildPath)
        // reports doesn't exist

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        let result = try service.clean(dryRun: false)

        #expect(result.buildRemoved == true)
        #expect(result.reportsRemoved == false)
        #expect(mockFileSystem.wasRemoved(buildPath))
        #expect(mockFileSystem.allRemovedPaths.count == 1)
    }

    // MARK: - Error Handling Tests

    @Test("Clean error has correct description", .tags(.unit, .errorHandling, .fast))
    func cleanErrorDescription() throws {
        let error = CleanError.removalFailed(path: "build", reason: "Permission denied")
        #expect(error.localizedDescription.contains("build"))
        #expect(error.localizedDescription.contains("Permission denied"))
    }

    @Test("Clean throws error when removal fails", .tags(.integration, .errorHandling))
    func cleanThrowsOnRemovalFailure() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let buildPath = tempDir.appendingPathComponent("build").path

        let mockFileSystem = MockFileSystemOperator()
        mockFileSystem.setExists(buildPath)
        let permissionError = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )
        mockFileSystem.setFailsRemoval(buildPath, error: permissionError)

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        #expect {
            _ = try service.clean(dryRun: false)
        } throws: { error in
            guard case CleanError.removalFailed = error else {
                return false
            }
            return true
        }
    }

    // MARK: - Custom Path Tests

    @Test("Clean uses custom build path from config", .tags(.integration))
    func cleanUsesCustomBuildPath() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
          build_path: custom-build
          reports_path: custom-reports
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let customBuildPath = tempDir.appendingPathComponent("custom-build").path
        let customReportsPath = tempDir.appendingPathComponent("custom-reports").path

        let mockFileSystem = MockFileSystemOperator()
        mockFileSystem.setExists(customBuildPath)
        mockFileSystem.setExists(customReportsPath)

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        let result = try service.clean(dryRun: false)

        #expect(result.buildPath == "custom-build")
        #expect(result.reportsPath == "custom-reports")
        #expect(mockFileSystem.wasRemoved(customBuildPath))
        #expect(mockFileSystem.wasRemoved(customReportsPath))
    }

    @Test("Clean honors absolute paths without appending to working directory", .tags(.integration))
    func cleanHonorsAbsolutePaths() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try TestFileHelper.createDummyProject(in: tempDir, name: "TestProject")

        // Use absolute paths in config
        let absoluteBuildPath = "/tmp/ci-build-artifacts"
        let absoluteReportsPath = "/tmp/ci-test-reports"

        let yamlContent = """
        app_name: TestApp
        project_path:
          cli: TestProject.xcodeproj
        xcode:
          version: "16.0"
          build_path: \(absoluteBuildPath)
          reports_path: \(absoluteReportsPath)
        """
        let configURL = tempDir.appendingPathComponent("Xproject.yml")
        try yamlContent.write(to: configURL, atomically: true, encoding: .utf8)

        let mockFileSystem = MockFileSystemOperator()
        // Set the absolute paths as existing (NOT working dir + path)
        mockFileSystem.setExists(absoluteBuildPath)
        mockFileSystem.setExists(absoluteReportsPath)

        let configService = ConfigurationService(
            workingDirectory: tempDir.path,
            customConfigPath: configURL.path
        )

        let service = CleanService(
            workingDirectory: tempDir.path,
            configurationProvider: configService,
            fileSystem: mockFileSystem
        )

        let result = try service.clean(dryRun: false)

        // Should use absolute paths directly, not append to working directory
        #expect(result.buildRemoved == true)
        #expect(result.reportsRemoved == true)
        #expect(mockFileSystem.wasRemoved(absoluteBuildPath))
        #expect(mockFileSystem.wasRemoved(absoluteReportsPath))

        // Verify it didn't try to remove the wrong nested path
        let wrongBuildPath = tempDir.appendingPathComponent(absoluteBuildPath).path
        #expect(!mockFileSystem.wasRemoved(wrongBuildPath))
    }
}
