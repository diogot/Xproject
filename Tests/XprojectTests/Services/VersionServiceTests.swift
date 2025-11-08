//
// VersionServiceTests.swift
// XprojectTests
//

import XCTest
@testable import Xproject

final class VersionServiceTests: XCTestCase {
    var mockExecutor: MockCommandExecutor!
    var service: VersionService!
    var workingDirectory: String!

    override func setUp() {
        super.setUp()
        // Create unique temp directory for this test run
        let tempDir = NSTemporaryDirectory()
        workingDirectory = (tempDir as NSString).appendingPathComponent("xproject-test-\(UUID().uuidString)")

        // Create working directory and test project
        try? FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        let projectPath = (workingDirectory as NSString).appendingPathComponent("TestApp.xcodeproj")
        try? FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

        mockExecutor = MockCommandExecutor(workingDirectory: workingDirectory)
        service = VersionService(workingDirectory: workingDirectory, executor: mockExecutor)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(atPath: workingDirectory)

        mockExecutor = nil
        service = nil
        workingDirectory = nil
        super.tearDown()
    }

    // MARK: - Get Current Version Tests

    func testGetCurrentVersionSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.2.3", error: "")
        )

        // When
        let version = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        XCTAssertEqual(version, Version(major: 1, minor: 2, patch: 3))
    }

    func testGetCurrentVersionWithoutPatch() throws {
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "2.1", error: "")
        )

        // When
        let version = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")

        // Then
        XCTAssertEqual(version, Version(major: 2, minor: 1, patch: 0))
    }

    func testGetCurrentVersionAgvtoolFailure() {
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "Info.plist not found")
        )

        // When/Then
        XCTAssertThrowsError(try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")) { error in
            guard case VersionServiceError.agvtoolFailed = error else {
                XCTFail("Expected agvtoolFailed error")
                return
            }
        }
    }

    func testGetCurrentVersionInvalidFormat() {
        // Given
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "invalid", error: "")
        )

        // When/Then
        XCTAssertThrowsError(try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")) { error in
            guard case VersionServiceError.invalidVersionFormat = error else {
                XCTFail("Expected invalidVersionFormat error")
                return
            }
        }
    }

    // MARK: - Set Version Tests

    func testSetVersionSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 2.0.0",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "Setting version to 2.0.0", error: "")
        )

        // When/Then
        XCTAssertNoThrow(
            try service.setVersion(
                Version(major: 2, minor: 0, patch: 0),
                target: "ios",
                projectPath: "TestApp.xcodeproj"
            )
        )
    }

    func testSetVersionFailure() {
        // Given
        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 2.0.0",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "Failed to set version")
        )

        // When/Then
        XCTAssertThrowsError(
            try service.setVersion(
                Version(major: 2, minor: 0, patch: 0),
                target: "ios",
                projectPath: "TestApp.xcodeproj"
            )
        ) { error in
            guard case VersionServiceError.agvtoolFailed = error else {
                XCTFail("Expected agvtoolFailed error")
                return
            }
        }
    }

    // MARK: - Get Current Build Tests

    func testGetCurrentBuildNoOffset() throws {
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "100", error: "")
        )

        // When
        let build = try service.getCurrentBuild(offset: 0)

        // Then
        XCTAssertEqual(build, 100)
    }

    func testGetCurrentBuildWithOffset() throws {
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "100", error: "")
        )

        // When
        let build = try service.getCurrentBuild(offset: -50)

        // Then
        XCTAssertEqual(build, 50)
    }

    func testGetCurrentBuildGitFailure() {
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "fatal: not a git repository")
        )

        // When/Then
        XCTAssertThrowsError(try service.getCurrentBuild(offset: 0)) { error in
            guard case VersionServiceError.gitFailed = error else {
                XCTFail("Expected gitFailed error")
                return
            }
        }
    }

    func testGetCurrentBuildInvalidNumber() {
        // Given
        mockExecutor.setResponse(
            for: "git rev-list HEAD --count",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "not-a-number", error: "")
        )

        // When/Then
        XCTAssertThrowsError(try service.getCurrentBuild(offset: 0)) { error in
            guard case VersionServiceError.invalidBuildNumber = error else {
                XCTFail("Expected invalidBuildNumber error")
                return
            }
        }
    }

    // MARK: - Bump Version Tests

    func testBumpVersionPatch() throws {
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
        XCTAssertEqual(newVersion, Version(major: 1, minor: 0, patch: 1))
    }

    func testBumpVersionMinor() throws {
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
        XCTAssertEqual(newVersion, Version(major: 1, minor: 3, patch: 0))
    }

    func testBumpVersionMajor() throws {
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
        XCTAssertEqual(newVersion, Version(major: 2, minor: 0, patch: 0))
    }

    // MARK: - Validation Tests

    func testValidateAgvtoolSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "which agvtool",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/usr/bin/agvtool", error: "")
        )

        // When/Then
        XCTAssertNoThrow(try service.validateAgvtool())
    }

    func testValidateAgvtoolNotFound() {
        // Given
        mockExecutor.setResponse(
            for: "which agvtool",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "")
        )

        // When/Then
        XCTAssertThrowsError(try service.validateAgvtool()) { error in
            guard case VersionServiceError.agvtoolNotFound = error else {
                XCTFail("Expected agvtoolNotFound error")
                return
            }
        }
    }

    func testValidateGitRepositorySuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --git-dir",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: ".git", error: "")
        )

        // When/Then
        XCTAssertNoThrow(try service.validateGitRepository())
    }

    func testValidateGitRepositoryNotFound() {
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --git-dir",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "fatal: not a git repository")
        )

        // When/Then
        XCTAssertThrowsError(try service.validateGitRepository()) { error in
            guard case VersionServiceError.notGitRepository = error else {
                XCTFail("Expected notGitRepository error")
                return
            }
        }
    }

    // MARK: - Subdirectory Project Tests

    func testGetVersionFromSubdirectoryProject() throws {
        // Given: Create subdirectory project structure
        let subdirPath = (workingDirectory as NSString).appendingPathComponent("TV")
        try? FileManager.default.createDirectory(atPath: subdirPath, withIntermediateDirectories: true)
        let projectPath = (subdirPath as NSString).appendingPathComponent("TV.xcodeproj")
        try? FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "3.0.0", error: "")
        )

        // When
        let version = try service.getCurrentVersion(target: "tvos", projectPath: "TV/TV.xcodeproj")

        // Then
        XCTAssertEqual(version, Version(major: 3, minor: 0, patch: 0))
    }

    func testSetVersionInSubdirectoryProject() throws {
        // Given: Create subdirectory project structure
        let subdirPath = (workingDirectory as NSString).appendingPathComponent("TV")
        try? FileManager.default.createDirectory(atPath: subdirPath, withIntermediateDirectories: true)
        let projectPath = (subdirPath as NSString).appendingPathComponent("TV.xcodeproj")
        try? FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

        mockExecutor.setResponse(
            for: "agvtool new-marketing-version 3.1.0",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "Setting version to 3.1.0", error: "")
        )

        // When/Then
        XCTAssertNoThrow(
            try service.setVersion(
                Version(major: 3, minor: 1, patch: 0),
                target: "tvos",
                projectPath: "TV/TV.xcodeproj"
            )
        )
    }

    // MARK: - Project Validation Tests

    func testProjectNotFoundError() {
        // Given: Project path that doesn't exist
        let nonExistentPath = "NonExistent/App.xcodeproj"

        // When/Then
        XCTAssertThrowsError(try service.getCurrentVersion(target: "ios", projectPath: nonExistentPath)) { error in
            guard case VersionServiceError.projectNotFound(let path) = error else {
                XCTFail("Expected projectNotFound error")
                return
            }
            XCTAssertEqual(path, nonExistentPath)
        }
    }

    func testProjectValidationWithRootLevelProject() throws {
        // Given: Root-level project (already created in setUp)
        mockExecutor.setResponse(
            for: "agvtool mvers -terse1",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "1.0.0", error: "")
        )

        // When: Access root-level project
        let version = try service.getCurrentVersion(target: "ios", projectPath: "TestApp.xcodeproj")

        // Then: Should work without error
        XCTAssertEqual(version, Version(major: 1, minor: 0, patch: 0))
    }
}
