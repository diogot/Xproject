//
// GitServiceTests.swift
// XprojectTests
//

import Testing
@testable import Xproject

func withGitService(_ test: (GitService, MockCommandExecutor) throws -> Void) rethrows {
    let workingDirectory = "/tmp/test-project"
    let mockExecutor = MockCommandExecutor(workingDirectory: workingDirectory)
    let service = GitService(workingDirectory: workingDirectory, executor: mockExecutor)

    try test(service, mockExecutor)
}

// MARK: - Repository Clean Tests

@Test
func isRepositoryCleanWhenClean() throws {
    try withGitService { service, mockExecutor in
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
        #expect(isClean)
    }
}

@Test
func isRepositoryCleanWithModifiedFiles() throws {
    try withGitService { service, mockExecutor in
        // Given
        mockExecutor.setResponse(
            for: "git diff --quiet",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "")
        )

        // When
        let isClean = try service.isRepositoryClean()

        // Then
        #expect(!isClean)
    }
}

@Test
func isRepositoryCleanWithUntrackedFiles() throws {
    try withGitService { service, mockExecutor in
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
        #expect(!isClean)
    }
}

// MARK: - Get Modified Files Tests

@Test
func getModifiedFilesWithNoChanges() throws {
    try withGitService { service, mockExecutor in
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
        #expect(files.isEmpty)
    }
}

@Test
func getModifiedFilesWithChanges() throws {
    try withGitService { service, mockExecutor in
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
        #expect(files.count == 3)
        #expect(files.contains("file1.swift"))
        #expect(files.contains("file2.swift"))
        #expect(files.contains("newfile.txt"))
    }
}

// MARK: - Commit Tests

@Test
func commitSuccess() throws {
    try withGitService { service, mockExecutor in
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
        try service.commit(message: "Test commit")
    }
}

@Test
func commitWithSpecificFiles() throws {
    try withGitService { service, mockExecutor in
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
        try service.commit(message: "Test commit", files: ["file1.swift", "file2.swift"])
    }
}

@Test
func commitFailure() {
    withGitService { service, mockExecutor in
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
        do {
            try service.commit(message: "Test commit")
            #expect(Bool(false), "Expected commitFailed error")
        } catch {
            guard case GitServiceError.commitFailed = error else {
                #expect(Bool(false), "Expected commitFailed error")
                return
            }
        }
    }
}

@Test
func commitVersionBumpSuccess() throws {
    try withGitService { service, mockExecutor in
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
        try service.commitVersionBump(
            version: Version(major: 1, minor: 0, patch: 0),
            build: 100,
            files: ["Test.xcodeproj/project.pbxproj", "Info.plist"]
        )
    }
}

@Test
func commitVersionBumpWithUnexpectedChanges() {
    withGitService { service, mockExecutor in
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
        do {
            try service.commitVersionBump(
                version: Version(major: 1, minor: 0, patch: 0),
                build: 100,
                files: ["Test.xcodeproj/project.pbxproj"]
            )
            #expect(Bool(false), "Expected unexpectedChanges error")
        } catch {
            guard case GitServiceError.unexpectedChanges = error else {
                #expect(Bool(false), "Expected unexpectedChanges error")
                return
            }
        }
    }
}

// MARK: - Tag Tests

@Test
func tagExistsTrue() throws {
    try withGitService { service, mockExecutor in
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "v1.0.0\n", error: "")
        )

        // When
        let exists = try service.tagExists("v1.0.0")

        // Then
        #expect(exists)
    }
}

@Test
func tagExistsFalse() throws {
    try withGitService { service, mockExecutor in
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let exists = try service.tagExists("v1.0.0")

        // Then
        #expect(!exists)
    }
}

@Test
func createTagSuccess() throws {
    try withGitService { service, mockExecutor in
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
        try service.createTag("v1.0.0")
    }
}

@Test
func createTagAlreadyExists() {
    withGitService { service, mockExecutor in
        // Given
        mockExecutor.setResponse(
            for: "git tag -l 'v1.0.0'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "v1.0.0\n", error: "")
        )

        // When/Then
        do {
            try service.createTag("v1.0.0")
            #expect(Bool(false), "Expected tagAlreadyExists error")
        } catch {
            guard case GitServiceError.tagAlreadyExists(let tag) = error else {
                #expect(Bool(false), "Expected tagAlreadyExists error")
                return
            }
            #expect(tag == "v1.0.0")
        }
    }
}

@Test
func createVersionTagWithoutEnvironment() throws {
    try withGitService { service, mockExecutor in
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
        #expect(tag == "ios/1.0.0-100")
    }
}

@Test
func createVersionTagWithEnvironment() throws {
    try withGitService { service, mockExecutor in
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
        #expect(tag == "production-ios/1.0.0-100")
    }
}

@Test
func createVersionTagWithCustomFormat() throws {
    try withGitService { service, mockExecutor in
        // Given - custom format: {target}-{env}/{version}-{build}
        mockExecutor.setResponse(
            for: "git tag -l 'ios-dev/1.0.0-100'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )
        mockExecutor.setResponse(
            for: "git tag 'ios-dev/1.0.0-100'",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "", error: "")
        )

        // When
        let tag = try service.createVersionTag(
            version: Version(major: 1, minor: 0, patch: 0),
            build: 100,
            target: "ios",
            environment: "dev",
            tagFormat: "{target}-{env}/{version}-{build}"
        )

        // Then
        #expect(tag == "ios-dev/1.0.0-100")
    }
}

// MARK: - Format Tag Tests

@Test
func formatTagWithCustomFormat() throws {
    try withGitService { service, _ in
        // Given
        let version = Version(major: 1, minor: 2, patch: 3)

        // When
        let tag = service.formatTag(
            format: "{target}-{env}/{version}-{build}",
            target: "ios",
            environment: "dev",
            version: version,
            build: 42
        )

        // Then
        #expect(tag == "ios-dev/1.2.3-42")
    }
}

@Test
func formatTagWithDefaultFormat() throws {
    try withGitService { service, _ in
        // Given
        let version = Version(major: 2, minor: 0, patch: 0)

        // When - nil format uses default: {target}/{version}-{build}
        let tag = service.formatTag(
            format: nil,
            target: "tvos",
            environment: nil,
            version: version,
            build: 150
        )

        // Then
        #expect(tag == "tvos/2.0.0-150")
    }
}

@Test
func formatTagWithoutEnvironment() throws {
    try withGitService { service, _ in
        // Given - format with {env} but no environment provided
        let version = Version(major: 1, minor: 0, patch: 0)

        // When - {env} should be stripped along with adjacent dash
        let tag = service.formatTag(
            format: "{target}-{env}/{version}-{build}",
            target: "ios",
            environment: nil,
            version: version,
            build: 100
        )

        // Then - "-{env}" is removed, leaving "ios/1.0.0-100"
        #expect(tag == "ios/1.0.0-100")
    }
}

@Test
func formatTagEnvPlaceholderVariants() throws {
    try withGitService { service, _ in
        // Given
        let version = Version(major: 1, minor: 0, patch: 0)

        // When/Then - test "{env}-" prefix removal
        let tag1 = service.formatTag(
            format: "{env}-{target}/{version}",
            target: "ios",
            environment: nil,
            version: version,
            build: 1
        )
        #expect(tag1 == "ios/1.0.0")

        // When/Then - test "-{env}" suffix removal
        let tag2 = service.formatTag(
            format: "{target}-{env}/{version}",
            target: "ios",
            environment: nil,
            version: version,
            build: 1
        )
        #expect(tag2 == "ios/1.0.0")

        // When/Then - test standalone "{env}" removal
        let tag3 = service.formatTag(
            format: "{env}/{target}/{version}",
            target: "ios",
            environment: nil,
            version: version,
            build: 1
        )
        #expect(tag3 == "ios/1.0.0")
    }
}

@Test
func formatTagWithEnvironmentProvided() throws {
    try withGitService { service, _ in
        // Given - format with env-first pattern
        let version = Version(major: 3, minor: 1, patch: 4)

        // When
        let tag = service.formatTag(
            format: "{env}-{target}/{version}-{build}",
            target: "ios",
            environment: "production",
            version: version,
            build: 200
        )

        // Then
        #expect(tag == "production-ios/3.1.4-200")
    }
}

// MARK: - Push Tests

@Test
func getCurrentBranchSuccess() throws {
    try withGitService { service, mockExecutor in
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --abbrev-ref HEAD",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "main\n", error: "")
        )

        // When
        let branch = try service.getCurrentBranch()

        // Then
        #expect(branch == "main")
    }
}

@Test
func getCurrentBranchFailure() {
    withGitService { service, mockExecutor in
        // Given
        mockExecutor.setResponse(
            for: "git rev-parse --abbrev-ref HEAD",
            response: MockCommandExecutor.MockResponse(exitCode: 1, output: "", error: "not a git repository")
        )

        // When/Then
        do {
            _ = try service.getCurrentBranch()
            #expect(Bool(false), "Expected unableToGetBranch error")
        } catch {
            guard case GitServiceError.unableToGetBranch = error else {
                #expect(Bool(false), "Expected unableToGetBranch error")
                return
            }
        }
    }
}

@Test
func pushWithTagsSuccess() throws {
    try withGitService { service, mockExecutor in
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
        try service.pushWithTags()
    }
}

@Test
func pushWithTagsFailure() {
    withGitService { service, mockExecutor in
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
        do {
            try service.pushWithTags()
            #expect(Bool(false), "Expected pushFailed error")
        } catch {
            guard case GitServiceError.pushFailed = error else {
                #expect(Bool(false), "Expected pushFailed error")
                return
            }
        }
    }
}

// MARK: - Error Message Tests

@Test
func repositoryDirtyErrorMessage() {
    // Given
    let files = ["file1.swift", "file2.swift", "newfile.txt"]
    let error = GitServiceError.repositoryDirty(files: files)

    // When
    let description = error.errorDescription

    // Then
    #expect(description != nil)
    #expect(description!.contains("Found unexpected uncommitted changes in the working directory"))
    #expect(description!.contains("file1.swift"))
    #expect(description!.contains("file2.swift"))
    #expect(description!.contains("newfile.txt"))
    #expect(description!.contains("Commit or stash your changes before creating a version tag"))
}
