//
// ConfigurationValidationTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("Configuration Validation Tests", .tags(.configValidation))
struct ConfigurationValidationTests {
    // MARK: - Helper Methods

    private func createMinimalConfig(
        releaseConfig: [String: ReleaseConfiguration]? = nil
    ) -> XprojectConfiguration {
        return XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: releaseConfig
            ),
            danger: nil
        )
    }

    private func createTempProjectDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a dummy project file
        let projectPath = tempDir.appendingPathComponent("Test.xcodeproj")
        try? FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        return tempDir
    }

    // MARK: - Release Configuration Field Tests

    @Test("validates release configuration with missing scheme")
    func testMissingSchemeValidation() throws {
        // Given
        let releaseConfig = ReleaseConfiguration(
            scheme: "",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates release configuration with missing output")
    func testMissingOutputValidation() throws {
        // Given
        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates release configuration with missing destination")
    func testMissingDestinationValidation() throws {
        // Given
        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates release configuration with missing type")
    func testMissingTypeValidation() throws {
        // Given
        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates release configuration with all required fields succeeds")
    func testValidReleaseConfiguration() throws {
        // Given
        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }

    // MARK: - Manual Signing Validation Tests

    @Test("validates manual signing requires signingCertificate")
    func testManualSigningRequiresCertificate() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: nil,
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: ["com.example.app": "Profile"]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates manual signing requires provisioning profiles")
    func testManualSigningRequiresProfiles() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: "iPhone Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: nil
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates manual signing with empty certificate")
    func testManualSigningWithEmptyCertificate() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: "",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: ["com.example.app": "Profile"]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates manual signing with empty provisioning profiles")
    func testManualSigningWithEmptyProfiles() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: "iPhone Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: [:]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates manual signing with all required fields succeeds")
    func testValidManualSigning() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: "iPhone Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: ["com.example.app": "Distribution Profile"]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }

    @Test("validates automatic signing allows nil certificate and profiles")
    func testAutomaticSigningAllowsNilFields() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: nil,
            teamID: "ABC123",
            signingStyle: "automatic",
            provisioningProfiles: nil
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }

    // MARK: - Multi-Environment Tests

    @Test("validates multiple release environments independently")
    func testMultipleEnvironmentsValidation() throws {
        // Given - One valid, one invalid
        let validRelease = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let invalidRelease = ReleaseConfiguration(
            scheme: "",  // Invalid
            configuration: "Debug",
            output: "MyApp-Dev",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: [
            "production": validRelease,
            "dev": invalidRelease
        ])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should throw due to invalid dev config
        #expect(throws: XprojectConfiguration.ValidationError.self) {
            try config.validate(baseDirectory: tempDir)
        }
    }

    @Test("validates iOS and tvOS configurations")
    func testIOSAndTVOSConfigurations() throws {
        // Given
        let iOSRelease = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "developer@example.com",
            signing: nil
        )

        let tvOSRelease = ReleaseConfiguration(
            scheme: "MyAppTV",
            configuration: "Release",
            output: "MyAppTV",
            destination: "tvOS",
            type: "appletvos",
            appStoreAccount: "developer@example.com",
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: [
            "production-ios": iOSRelease,
            "production-tvos": tvOSRelease
        ])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }

    @Test("validates dev and production environments with different signing")
    func testDevAndProductionSigningConfigurations() throws {
        // Given
        let devRelease = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Debug",
            output: "MyApp-Dev",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: SigningConfiguration(
                signingCertificate: nil,
                teamID: "ABC123",
                signingStyle: "automatic",
                provisioningProfiles: nil
            )
        )

        let prodRelease = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "developer@example.com",
            signing: SigningConfiguration(
                signingCertificate: "iPhone Distribution",
                teamID: "ABC123",
                signingStyle: "manual",
                provisioningProfiles: ["com.example.app": "Distribution Profile"]
            )
        )

        let config = createMinimalConfig(releaseConfig: [
            "dev-ios": devRelease,
            "production-ios": prodRelease
        ])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }

    @Test("validates manual signing with multiple bundle IDs")
    func testManualSigningMultipleBundleIDs() throws {
        // Given
        let signing = SigningConfiguration(
            signingCertificate: "iPhone Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: [
                "com.example.app": "Main App Profile",
                "com.example.app.extension": "Extension Profile",
                "com.example.app.widget": "Widget Profile"
            ]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "developer@example.com",
            signing: signing
        )

        let config = createMinimalConfig(releaseConfig: ["production": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }

    @Test("validates configuration without app_store_account is valid")
    func testConfigurationWithoutAppStoreAccount() throws {
        // Given
        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Debug",
            output: "MyApp-Dev",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = createMinimalConfig(releaseConfig: ["dev": releaseConfig])
        let tempDir = createTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // When/Then - Should not throw
        try config.validate(baseDirectory: tempDir)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var configValidation: Self
}
