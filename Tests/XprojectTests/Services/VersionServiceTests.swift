//
// VersionServiceTests.swift
// XprojectTests
//

import Foundation
import Testing
@testable import Xproject

func withVersionService(_ test: (VersionService, MockCommandExecutor, String) throws -> Void) throws {
    let tempDir = NSTemporaryDirectory()
    let workingDirectory = (tempDir as NSString).appendingPathComponent("xproject-test-\(UUID().uuidString)")

    defer {
        try? FileManager.default.removeItem(atPath: workingDirectory)
    }

    try FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
    let projectPath = (workingDirectory as NSString).appendingPathComponent("TestApp.xcodeproj")
    try FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

    let mockExecutor = MockCommandExecutor(workingDirectory: workingDirectory)
    let service = VersionService(workingDirectory: workingDirectory, executor: mockExecutor)

    try test(service, mockExecutor, workingDirectory)
}

// MARK: - Get Current Version Tests

@Test
func getCurrentVersionSuccess() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.2.3", error: "")
        )

        // When
        let version = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        #expect(version == Version(major: 1, minor: 2, patch: 3))
    }
}

@Test
func getCurrentVersionWithoutPatch() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "2.1", error: "")
        )

        // When
        let version = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        #expect(version == Version(major: 2, minor: 1, patch: 0))
    }
}

@Test
func getCurrentVersionAgvtoolFailure() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "Info.plist not found")
        )

        // When/Then
        do {
            _ = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .agvtoolFailed = error else {
                #expect(Bool(false), "Expected agvtoolFailed error")
                return
            }
        }
    }
}

@Test
func getCurrentVersionInvalidFormat() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "invalid", error: "")
        )

        // When/Then
        do {
            _ = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .invalidVersionFormat = error else {
                #expect(Bool(false), "Expected invalidVersionFormat error")
                return
            }
        }
    }
}

// MARK: - Set Version Tests

@Test
func setVersionSuccess() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 2.0.0",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "Setting version to 2.0.0", error: "")
        )

        // When/Then
        try service.setVersion(
            Version(major: 2, minor: 0, patch: 0),
            target: "ios",
            projectPath: "TestApp.xcodeproj"
        )
    }
}

@Test
func setVersionFailure() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 2.0.0",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "Failed to set version")
        )

        // When/Then
        do {
            try service.setVersion(
                Version(major: 2, minor: 0, patch: 0),
                target: "ios",
                projectPath: "TestApp.xcodeproj"
            )
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .agvtoolFailed = error else {
                #expect(Bool(false), "Expected agvtoolFailed error")
                return
            }
        }
    }
}

// MARK: - Get Current Build Tests

@Test
func getCurrentBuildNoOffset() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "100", error: "")
        )

        // When
        let build = try service.getCurrentBuild(offset: 0)

        // Then
        #expect(build == 100)
    }
}

@Test
func getCurrentBuildWithOffset() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "100", error: "")
        )

        // When
        let build = try service.getCurrentBuild(offset: -50)

        // Then
        #expect(build == 50)
    }
}

@Test
func getCurrentBuildGitFailure() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "fatal: not a git repository")
        )

        // When/Then
        do {
            _ = try service.getCurrentBuild(offset: 0)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .gitFailed = error else {
                #expect(Bool(false), "Expected gitFailed error")
                return
            }
        }
    }
}

@Test
func getCurrentBuildInvalidNumber() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "not-a-number", error: "")
        )

        // When/Then
        do {
            _ = try service.getCurrentBuild(offset: 0)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .invalidBuildNumber = error else {
                #expect(Bool(false), "Expected invalidBuildNumber error")
                return
            }
        }
    }
}

// MARK: - Bump Version Tests

@Test
func bumpVersionPatch() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.0.0", error: "")
        )
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 1.0.1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "OK", error: "")
        )

        // When
        let newVersion = try service.bumpVersion(.patch, target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        #expect(newVersion == Version(major: 1, minor: 0, patch: 1))
    }
}

@Test
func bumpVersionMinor() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.2.3", error: "")
        )
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 1.3.0",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "OK", error: "")
        )

        // When
        let newVersion = try service.bumpVersion(.minor, target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        #expect(newVersion == Version(major: 1, minor: 3, patch: 0))
    }
}

@Test
func bumpVersionMajor() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.2.3", error: "")
        )
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 2.0.0",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "OK", error: "")
        )

        // When
        let newVersion = try service.bumpVersion(.major, target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        #expect(newVersion == Version(major: 2, minor: 0, patch: 0))
    }
}

// MARK: - Validation Tests

@Test
func validateAgvtoolSuccess() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "which agvtool",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/usr/bin/agvtool", error: "")
        )

        // When/Then
        try service.validateAgvtool()
    }
}

@Test
func validateAgvtoolNotFound() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "which agvtool",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "")
        )

        // When/Then
        do {
            try service.validateAgvtool()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .agvtoolNotFound = error else {
                #expect(Bool(false), "Expected agvtoolNotFound error")
                return
            }
        }
    }
}

@Test
func validateGitRepositorySuccess() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --git-dir",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: ".git", error: "")
        )

        // When/Then
        try service.validateGitRepository()
    }
}

@Test
func validateGitRepositoryNotFound() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --git-dir",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "fatal: not a git repository")
        )

        // When/Then
        do {
            try service.validateGitRepository()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .notGitRepository = error else {
                #expect(Bool(false), "Expected notGitRepository error")
                return
            }
        }
    }
}

// MARK: - Subdirectory Project Tests

@Test
func getVersionFromSubdirectoryProject() throws {
    try withVersionService { service, mockExecutor, workingDirectory in
        // Given: Create subdirectory project structure
        let subdirPath = (workingDirectory as NSString).appendingPathComponent("TV")
        try FileManager.default.createDirectory(atPath: subdirPath, withIntermediateDirectories: true)
        let projectPath = (subdirPath as NSString).appendingPathComponent("TV.xcodeproj")
        try FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "3.0.0", error: "")
        )

        // When
        let version = try service.getCurrentVersion(target: "tvos", projectPath: "TV/TV.xcodeproj")

        // Then
        #expect(version == Version(major: 3, minor: 0, patch: 0))
    }
}

@Test
func setVersionInSubdirectoryProject() throws {
    try withVersionService { service, mockExecutor, workingDirectory in
        // Given: Create subdirectory project structure
        let subdirPath = (workingDirectory as NSString).appendingPathComponent("TV")
        try FileManager.default.createDirectory(atPath: subdirPath, withIntermediateDirectories: true)
        let projectPath = (subdirPath as NSString).appendingPathComponent("TV.xcodeproj")
        try FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 3.1.0",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "Setting version to 3.1.0", error: "")
        )

        // When/Then
        try service.setVersion(
            Version(major: 3, minor: 1, patch: 0),
            target: "tvos",
            projectPath: "TV/TV.xcodeproj"
        )
    }
}

// MARK: - Project Validation Tests

@Test
func projectNotFoundError() throws {
    try withVersionService { service, _, _ in
        // Given: Project path that doesn't exist
        let nonExistentPath = "NonExistent/App.xcodeproj"

        // When/Then
        do {
            _ = try service.getCurrentVersion(target: "ios", projectPath: nonExistentPath)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as VersionServiceError {
            guard case .projectNotFound(let path) = error else {
                #expect(Bool(false), "Expected projectNotFound error")
                return
            }
            #expect(path == nonExistentPath)
        }
    }
}

@Test
func projectValidationWithRootLevelProject() throws {
    try withVersionService { service, mockExecutor, _ in
        // Given: Root-level project (already created in withVersionService)
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.0.0", error: "")
        )

        // When: Access root-level project
        let version = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")

        // Then: Should work without error
        #expect(version == Version(major: 1, minor: 0, patch: 0))
    }
}
