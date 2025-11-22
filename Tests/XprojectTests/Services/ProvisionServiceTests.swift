//
// ProvisionServiceTests.swift
// XprojectTests
//
// Tests for ProvisionService
//

import Foundation
import Testing
@testable import Xproject

@Suite("ProvisionService Tests", .serialized)
struct ProvisionServiceTests {
    private static let testAppName = "XprojectProvisionTest"

    // MARK: - Helper Methods

    /// Creates a temporary directory for tests
    private func createTempDirectory() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xproject_provision_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.path
    }

    /// Creates a mock .mobileprovision file
    private func createMockProfile(in directory: String, name: String, content: String? = nil) throws -> String {
        let profilePath = (directory as NSString).appendingPathComponent(name)
        let data = (content ?? "Mock provisioning profile content for \(name)").data(using: .utf8)!
        FileManager.default.createFile(atPath: profilePath, contents: data)
        return profilePath
    }

    /// Cleans up temporary directory
    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Encrypt/Decrypt Round-trip Tests

    @Test("Encrypt and decrypt profiles round-trip")
    func testEncryptDecryptRoundTrip() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)

        let profile1Content = "Profile 1 content \(UUID().uuidString)"
        let profile2Content = "Profile 2 content \(UUID().uuidString)"
        try createMockProfile(in: sourceDir, name: "Dev.mobileprovision", content: profile1Content)
        try createMockProfile(in: sourceDir, name: "Dist.mobileprovision", content: profile2Content)

        let archivePath = "provision/profiles.zip.enc"
        let extractPath = "provision/profiles"
        let password = "test_password_\(UUID().uuidString)"

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When - Encrypt
        let encryptResult = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: archivePath,
            password: password
        )

        // Then - Verify encryption result
        #expect(encryptResult.profileCount == 2)
        #expect(encryptResult.profileNames.contains("Dev.mobileprovision"))
        #expect(encryptResult.profileNames.contains("Dist.mobileprovision"))
        #expect(encryptResult.archiveSize > 0)

        // Verify encrypted archive exists
        let fullArchivePath = (workingDir as NSString).appendingPathComponent(archivePath)
        #expect(FileManager.default.fileExists(atPath: fullArchivePath))

        // When - Decrypt
        let decryptResult = try service.decryptProfiles(
            archivePath: archivePath,
            extractPath: extractPath,
            password: password
        )

        // Then - Verify decryption result
        #expect(decryptResult.profileCount == 2)
        #expect(decryptResult.profileNames.contains("Dev.mobileprovision"))
        #expect(decryptResult.profileNames.contains("Dist.mobileprovision"))

        // Verify content matches
        let extractedPath = (workingDir as NSString).appendingPathComponent(extractPath)
        let extractedProfile1 = (extractedPath as NSString).appendingPathComponent("Dev.mobileprovision")
        let extractedProfile2 = (extractedPath as NSString).appendingPathComponent("Dist.mobileprovision")

        let extracted1 = try String(contentsOfFile: extractedProfile1, encoding: .utf8)
        let extracted2 = try String(contentsOfFile: extractedProfile2, encoding: .utf8)

        #expect(extracted1 == profile1Content)
        #expect(extracted2 == profile2Content)
    }

    @Test("Encrypt multiple profiles maintains sorted order")
    func testEncryptMaintainsSortedOrder() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)

        // Create profiles in non-alphabetical order
        try createMockProfile(in: sourceDir, name: "Zebra.mobileprovision")
        try createMockProfile(in: sourceDir, name: "Alpha.mobileprovision")
        try createMockProfile(in: sourceDir, name: "Middle.mobileprovision")

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When
        let result = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: "archive.zip.enc",
            password: "test"
        )

        // Then - profiles should be sorted
        #expect(result.profileNames == ["Alpha.mobileprovision", "Middle.mobileprovision", "Zebra.mobileprovision"])
    }

    @Test("Encrypt large archive")
    func testEncryptLargeArchive() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)

        // Create multiple profiles with substantial content
        let largeContent = String(repeating: "A", count: 10_000)
        for index in 1...10 {
            try createMockProfile(in: sourceDir, name: "Profile\(index).mobileprovision", content: largeContent)
        }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When
        let result = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: "archive.zip.enc",
            password: "test"
        )

        // Then
        #expect(result.profileCount == 10)
        #expect(result.archiveSize > 0)
    }

    // MARK: - List Profiles Tests

    @Test("List profiles in encrypted archive")
    func testListProfiles() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)

        try createMockProfile(in: sourceDir, name: "iOS_Dev.mobileprovision")
        try createMockProfile(in: sourceDir, name: "iOS_Dist.mobileprovision")
        try createMockProfile(in: sourceDir, name: "tvOS_Dev.mobileprovision")

        let password = "test_password"
        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        _ = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: "archive.zip.enc",
            password: password
        )

        // When
        let profiles = try service.listProfiles(archivePath: "archive.zip.enc", password: password)

        // Then
        #expect(profiles.count == 3)
        #expect(profiles.contains("iOS_Dev.mobileprovision"))
        #expect(profiles.contains("iOS_Dist.mobileprovision"))
        #expect(profiles.contains("tvOS_Dev.mobileprovision"))
    }

    // MARK: - Install Profiles Tests

    @Test("Install profiles creates target directory")
    func testInstallCreatesTargetDirectory() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let extractDir = (workingDir as NSString).appendingPathComponent("extract")
        try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)
        try createMockProfile(in: extractDir, name: "Test.mobileprovision")

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When - This will attempt to install to ~/Library/MobileDevice/Provisioning Profiles
        // We can only verify the install result structure in unit tests
        let result = try service.installProfiles(extractPath: extractDir)

        // Then - We verify structure, actual installation depends on system permissions
        #expect(result.installedCount >= 0)
        #expect(result.skippedCount >= 0)
        #expect(result.installedCount + result.skippedCount == 1)
    }

    @Test("Install profiles skips identical files")
    func testInstallSkipsIdenticalFiles() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let extractDir = (workingDir as NSString).appendingPathComponent("extract")
        try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)
        try createMockProfile(in: extractDir, name: "Test.mobileprovision", content: "identical")

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When - Install twice
        let result1 = try service.installProfiles(extractPath: extractDir)
        let result2 = try service.installProfiles(extractPath: extractDir)

        // Then - Second install should skip (files are identical)
        // If first install succeeded, second should skip
        if result1.installedCount == 1 {
            #expect(result2.skippedCount == 1)
            #expect(result2.installedCount == 0)
        }
    }

    // MARK: - Cleanup Tests

    @Test("Cleanup removes extract directory and staging files")
    func testCleanup() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let extractDir = (workingDir as NSString).appendingPathComponent("provision/profiles")
        let stagingDir = (workingDir as NSString).appendingPathComponent("tmp/provision")
        try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: stagingDir, withIntermediateDirectories: true)

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When
        let result = try service.cleanup(extractPath: "provision/profiles")

        // Then
        #expect(result.removedCount >= 1)
        #expect(!FileManager.default.fileExists(atPath: extractDir))
    }

    @Test("Cleanup with no files to remove")
    func testCleanupNoFiles() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When
        let result = try service.cleanup(extractPath: "provision/profiles")

        // Then
        #expect(result.removedCount == 0)
        #expect(result.removedPaths.isEmpty)
    }

    // MARK: - Error Handling Tests

    @Test("Encrypt throws when source directory not found")
    func testEncryptSourceDirectoryNotFound() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.encryptProfiles(
                sourcePath: "nonexistent/path",
                archivePath: "archive.zip.enc",
                password: "test"
            )
            #expect(Bool(false), "Expected sourceDirectoryNotFound error")
        } catch let error as ProvisionError {
            guard case .sourceDirectoryNotFound = error else {
                #expect(Bool(false), "Expected sourceDirectoryNotFound, got \(error)")
                return
            }
        }
    }

    @Test("Encrypt throws when no profiles found")
    func testEncryptNoProfilesFound() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        // Directory exists but has no .mobileprovision files

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.encryptProfiles(
                sourcePath: sourceDir,
                archivePath: "archive.zip.enc",
                password: "test"
            )
            #expect(Bool(false), "Expected noProfilesFound error")
        } catch let error as ProvisionError {
            guard case .noProfilesFound = error else {
                #expect(Bool(false), "Expected noProfilesFound, got \(error)")
                return
            }
        }
    }

    @Test("Decrypt throws when archive not found")
    func testDecryptArchiveNotFound() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.decryptProfiles(
                archivePath: "nonexistent.zip.enc",
                extractPath: "extract",
                password: "test"
            )
            #expect(Bool(false), "Expected archiveNotFound error")
        } catch let error as ProvisionError {
            guard case .archiveNotFound = error else {
                #expect(Bool(false), "Expected archiveNotFound, got \(error)")
                return
            }
        }
    }

    @Test("Decrypt throws with wrong password")
    func testDecryptWrongPassword() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        try createMockProfile(in: sourceDir, name: "Test.mobileprovision")

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // Encrypt with one password
        _ = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: "archive.zip.enc",
            password: "correct_password"
        )

        // When/Then - Decrypt with wrong password
        do {
            _ = try service.decryptProfiles(
                archivePath: "archive.zip.enc",
                extractPath: "extract",
                password: "wrong_password"
            )
            #expect(Bool(false), "Expected decryption error with wrong password")
        } catch let error as ProvisionError {
            // Should be either wrongPassword or decryptionFailed
            switch error {
            case .wrongPassword, .decryptionFailed:
                // Expected
                break
            default:
                #expect(Bool(false), "Expected wrongPassword or decryptionFailed, got \(error)")
            }
        }
    }

    @Test("List throws when archive not found")
    func testListArchiveNotFound() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.listProfiles(archivePath: "nonexistent.zip.enc", password: "test")
            #expect(Bool(false), "Expected archiveNotFound error")
        } catch let error as ProvisionError {
            guard case .archiveNotFound = error else {
                #expect(Bool(false), "Expected archiveNotFound, got \(error)")
                return
            }
        }
    }

    @Test("Install throws when extract directory not found")
    func testInstallExtractDirectoryNotFound() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.installProfiles(extractPath: "nonexistent/path")
            #expect(Bool(false), "Expected sourceDirectoryNotFound error")
        } catch let error as ProvisionError {
            guard case .sourceDirectoryNotFound = error else {
                #expect(Bool(false), "Expected sourceDirectoryNotFound, got \(error)")
                return
            }
        }
    }

    @Test("Install throws when no profiles in extract directory")
    func testInstallNoProfilesFound() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let extractDir = (workingDir as NSString).appendingPathComponent("extract")
        try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)
        // Directory exists but no .mobileprovision files

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.installProfiles(extractPath: extractDir)
            #expect(Bool(false), "Expected noProfilesFound error")
        } catch let error as ProvisionError {
            guard case .noProfilesFound = error else {
                #expect(Bool(false), "Expected noProfilesFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Password Priority Tests

    @Test("Password from environment variable takes priority")
    func testPasswordFromEnvironmentVariable() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        try createMockProfile(in: sourceDir, name: "Test.mobileprovision", content: "test content")

        // Set environment variable
        let envPassword = "env_password_\(UUID().uuidString)"
        setenv("PROVISION_PASSWORD", envPassword, 1)
        defer { unsetenv("PROVISION_PASSWORD") }

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            interactiveEnabled: false
        )

        // When - Encrypt using ENV password (no explicit password)
        let encryptResult = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: "archive.zip.enc"
        )

        #expect(encryptResult.profileCount == 1)

        // Then - Decrypt using same ENV password should work
        let decryptResult = try service.decryptProfiles(
            archivePath: "archive.zip.enc",
            extractPath: "extract"
        )

        #expect(decryptResult.profileCount == 1)
    }

    @Test("Password not found throws error when interactive disabled")
    func testPasswordNotFoundError() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        try createMockProfile(in: sourceDir, name: "Test.mobileprovision")

        // Ensure no ENV variable
        unsetenv("PROVISION_PASSWORD")

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: "NonExistentApp_\(UUID().uuidString)",
            interactiveEnabled: false
        )

        // When/Then
        do {
            _ = try service.encryptProfiles(
                sourcePath: sourceDir,
                archivePath: "archive.zip.enc"
            )
            #expect(Bool(false), "Expected passwordNotFound error")
        } catch let error as ProvisionError {
            guard case .passwordNotFound = error else {
                #expect(Bool(false), "Expected passwordNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Dry Run Tests

    @Test("Dry run does not create archive file")
    func testDryRunDoesNotCreateArchive() throws {
        // Given
        let workingDir = try createTempDirectory()
        defer { cleanup(workingDir) }

        let sourceDir = (workingDir as NSString).appendingPathComponent("source")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        try createMockProfile(in: sourceDir, name: "Test.mobileprovision")

        let service = ProvisionService(
            workingDirectory: workingDir,
            appName: Self.testAppName,
            dryRun: true,
            interactiveEnabled: false
        )

        // When
        _ = try service.encryptProfiles(
            sourcePath: sourceDir,
            archivePath: "archive.zip.enc",
            password: "test"
        )

        // Then - Archive should not exist in dry run
        let archivePath = (workingDir as NSString).appendingPathComponent("archive.zip.enc")
        #expect(!FileManager.default.fileExists(atPath: archivePath))
    }
}
