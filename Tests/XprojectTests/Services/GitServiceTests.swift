//
// GitServiceTests.swift
// XprojectTests
//

import XCTest
@testable import Xproject

final class GitServiceTests: XCTestCase {
    var mockExecutor: MockCommandExecutor!
    var service: GitService!
    var workingDirectory: String!

    override func setUp() {
        super.setUp()
        workingDirectory = "/tmp/test-project"
        mockExecutor = MockCommandExecutor(workingDirectory: workingDirectory)
        service = GitService(workingDirectory: workingDirectory, executor: mockExecutor)
    }

    override func tearDown() {
        mockExecutor = nil
        service = nil
        workingDirectory = nil
        super.tearDown()
    }

    // MARK: - Repository Clean Tests

    func testIsRepositoryCleanWhenClean() throws {
        // Given
        mockExecutor.setResponse(
            for: "git diff --quiet",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git ls-files --other --exclude-standard",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let isClean = try service.isRepositoryClean()

        // Then
        XCTAssertTrue(isClean)
    }

    func testIsRepositoryCleanWithModifiedFiles() throws {
        // Given
        mockExecutor.setResponse(
            for: "git diff --quiet",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "")
        )

        // When
        let isClean = try service.isRepositoryClean()

        // Then
        XCTAssertFalse(isClean)
    }

    func testIsRepositoryCleanWithUntrackedFiles() throws {
        // Given
        mockExecutor.setResponse(
            for: "git diff --quiet",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git ls-files --other --exclude-standard",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "newfile.txt\n", error: "")
        )

        // When
        let isClean = try service.isRepositoryClean()

        // Then
        XCTAssertFalse(isClean)
    }

    // MARK: - Get Modified Files Tests

    func testGetModifiedFilesWithNoChanges() throws {
        // Given
        mockExecutor.setResponse(
            for: "git diff --name-only",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git ls-files --other --exclude-standard",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let files = try service.getModifiedFiles()

        // Then
        XCTAssertTrue(files.isEmpty)
    }

    func testGetModifiedFilesWithChanges() throws {
        // Given
        mockExecutor.setResponse(
            for: "git diff --name-only",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "file1.swift\nfile2.swift\n", error: "")
        )
        mockExecutor.setResponse(
            for: "git ls-files --other --exclude-standard",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "newfile.txt\n", error: "")
        )

        // When
        let files = try service.getModifiedFiles()

        // Then
        XCTAssertEqual(files.count, 3)
        XCTAssertTrue(files.contains("file1.swift"))
        XCTAssertTrue(files.contains("file2.swift"))
        XCTAssertTrue(files.contains("newfile.txt"))
    }

    // MARK: - Commit Tests

    func testCommitSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "git add -A",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "/usr/bin/git commit -m Test commit",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "[main abc1234] Test commit", error: "")
        )

        // When/Then
        XCTAssertNoThrow(try service.commit(message: "Test commit"))
    }

    func testCommitWithSpecificFiles() throws {
        // Given
        mockExecutor.setResponse(
            for: "/usr/bin/git add file1.swift",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "/usr/bin/git add file2.swift",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "/usr/bin/git commit -m Test commit",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When/Then
        XCTAssertNoThrow(try service.commit(message: "Test commit", files: ["file1.swift", "file2.swift"]))
    }

    func testCommitFailure() {
        // Given
        mockExecutor.setResponse(
            for: "git add -A",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "/usr/bin/git commit -m Test commit",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "nothing to commit")
        )

        // When/Then
        XCTAssertThrowsError(try service.commit(message: "Test commit")) { error in
            guard case GitServiceError.commitFailed = error else {
                XCTFail("Expected commitFailed error")
                return
            }
        }
    }

    func testCommitVersionBumpSuccess() throws {
        // Given - Setup modified files check
        mockExecutor.setResponse(
            for: "git diff --name-only",
            response: MockCommandExecutor.MockResponse(
                exitCode: 0,
                output: "Test.xcodeproj/project.pbxproj\nInfo.plist\n",
                error: ""
            )
        )
        mockExecutor.setResponse(
            for: "git ls-files --other --exclude-standard",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // Setup commit operations
        mockExecutor.setResponse(
            for: "/usr/bin/git add Test.xcodeproj/project.pbxproj",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "/usr/bin/git add Info.plist",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "/usr/bin/git commit -m [skip ci] Bumping build number to 1.0.0-100",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When/Then
        XCTAssertNoThrow(
            try service.commitVersionBump(
                version: Version(major: 1, minor: 0, patch: 0),
                build: 100,
                files: ["Test.xcodeproj/project.pbxproj", "Info.plist"]
            )
        )
    }

    func testCommitVersionBumpWithUnexpectedChanges() {
        // Given
        mockExecutor.setResponse(
            for: "git diff --name-only",
            response: MockCommandExecutor.MockResponse(
                exitCode: 0,
                output: "Test.xcodeproj/project.pbxproj\nUnexpected.swift\n",
                error: ""
            )
        )
        mockExecutor.setResponse(
            for: "git ls-files --other --exclude-standard",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When/Then
        XCTAssertThrowsError(
            try service.commitVersionBump(
                version: Version(major: 1, minor: 0, patch: 0),
                build: 100,
                files: ["Test.xcodeproj/project.pbxproj"]
            )
        ) { error in
            guard case GitServiceError.unexpectedChanges = error else {
                XCTFail("Expected unexpectedChanges error")
                return
            }
        }
    }

    // MARK: - Tag Tests

    func testTagExistsTrue() throws {
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "v1.0.0\n", error: "")
        )

        // When
        let exists = try service.tagExists("v1.0.0")

        // Then
        XCTAssertTrue(exists)
    }

    func testTagExistsFalse() throws {
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let exists = try service.tagExists("v1.0.0")

        // Then
        XCTAssertFalse(exists)
    }

    func testCreateTagSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git tag 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When/Then
        XCTAssertNoThrow(try service.createTag("v1.0.0"))
    }

    func testCreateTagAlreadyExists() {
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "v1.0.0\n", error: "")
        )

        // When/Then
        XCTAssertThrowsError(try service.createTag("v1.0.0")) { error in
            guard case GitServiceError.tagAlreadyExists(let tag) = error else {
                XCTFail("Expected tagAlreadyExists error")
                return
            }
            XCTAssertEqual(tag, "v1.0.0")
        }
    }

    func testCreateVersionTagWithoutEnvironment() throws {
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'ios/1.0.0-100'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git tag 'ios/1.0.0-100'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let tag = try service.createVersionTag(
            version: Version(major: 1, minor: 0, patch: 0),
            build: 100,
            target: "ios"
        )

        // Then
        XCTAssertEqual(tag, "ios/1.0.0-100")
    }

    func testCreateVersionTagWithEnvironment() throws {
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'production-ios/1.0.0-100'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git tag 'production-ios/1.0.0-100'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let tag = try service.createVersionTag(
            version: Version(major: 1, minor: 0, patch: 0),
            build: 100,
            target: "ios",
            environment: "production"
        )

        // Then
        XCTAssertEqual(tag, "production-ios/1.0.0-100")
    }

    // MARK: - Push Tests

    func testGetCurrentBranchSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --abbrev-ref HEAD",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "main\n", error: "")
        )

        // When
        let branch = try service.getCurrentBranch()

        // Then
        XCTAssertEqual(branch, "main")
    }

    func testGetCurrentBranchFailure() {
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --abbrev-ref HEAD",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "not a git repository")
        )

        // When/Then
        XCTAssertThrowsError(try service.getCurrentBranch()) { error in
            guard case GitServiceError.unableToGetBranch = error else {
                XCTFail("Expected unableToGetBranch error")
                return
            }
        }
    }

    func testPushWithTagsSuccess() throws {
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --abbrev-ref HEAD",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "main\n", error: "")
        )
        mockExecutor.setResponse(
            for: "git push origin main --tags",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "Everything up-to-date", error: "")
        )

        // When/Then
        XCTAssertNoThrow(try service.pushWithTags())
    }

    func testPushWithTagsFailure() {
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --abbrev-ref HEAD",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "main\n", error: "")
        )
        mockExecutor.setResponse(
            for: "git push origin main --tags",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "Permission denied")
        )

        // When/Then
        XCTAssertThrowsError(try service.pushWithTags()) { error in
            guard case GitServiceError.pushFailed = error else {
                XCTFail("Expected pushFailed error")
                return
            }
        }
    }
}
