//
// XcodeClientTests.swift
// XProject
//

import Foundation
import Testing
@testable import XProject

@Suite("XcodeClient Tests", .tags(.xcodeClient))
struct XcodeClientTests {
    @Test("XcodeClient can be instantiated")
    func testXcodeClientInstantiation() throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockConfigProvider = MockConfigurationProvider(
            config: XProjectConfiguration(
                appName: "TestApp",
                workspacePath: nil,
                projectPaths: ["test": "Test.xcodeproj"],
                setup: nil,
                xcode: nil,
                danger: nil
            )
        )

        // When
        let xcodeClient = XcodeClient(
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor
        )

        // Then - just verify it's created successfully
        #expect(type(of: xcodeClient) == XcodeClient.self)
    }

    @Test("XcodeClient clean removes build artifacts")
    func testClean() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Mock configuration with build paths
        let config = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: nil
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor
        ) { mockFileManager }

        // When
        try await xcodeClient.clean()

        // Then
        #expect(mockExecutor.executedCommands.count == 1)
        #expect(mockExecutor.executedCommands[0].command.contains("rm -rf"))
        #expect(mockExecutor.executedCommands[0].command.contains("build"))
        #expect(mockExecutor.executedCommands[0].command.contains("reports"))
    }

    @Test("BuildService handles missing Xcode configuration gracefully")
    func testMissingXcodeConfig() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()

        // Mock configuration without xcode configuration
        let config = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: nil,
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor
        )

        // When/Then
        do {
            try await xcodeClient.archive(environment: "test")
            #expect(Bool(false), "Should have thrown an error")
        } catch XcodeClientError.environmentNotFound {
            // Expected error
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("BuildService uses FileManager builder pattern correctly")
    func testFileManagerBuilderPattern() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Mock configuration with build paths
        let config = XProjectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "15.0",
                buildPath: "custom-build",
                reportsPath: "custom-reports",
                tests: nil,
                release: nil
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)

        let xcodeClient = XcodeClient(
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor
        ) { mockFileManager }

        // When - Test the builder pattern by accessing createDirectoriesIfNeeded indirectly
        // We'll test this by trying to build for testing but expect it to fail gracefully
        // The important part is that directories get created first

        // This should call createDirectoriesIfNeeded which uses our builder
        // It will fail on Xcode commands but that's ok for this test
        do {
            try await xcodeClient.buildForTesting(
                scheme: "TestScheme",
                clean: false,
                buildDestination: "generic/platform=iOS Simulator"
            )
        } catch {
            // Expected to fail, we just want to test directory creation
        }

        // Then - Verify FileManager builder was used and directories were created
        #expect(mockFileManager.createdDirectories.count == 2)
        #expect(mockFileManager.createdDirectories.contains("custom-build"))
        #expect(mockFileManager.createdDirectories.contains("custom-reports"))
    }

    @Test("SigningConfiguration struct works correctly")
    func testSigningConfiguration() throws {
        // Given - Create a signing configuration with all fields
        let signingConfig = SigningConfiguration(
            signingCertificate: "iPhone Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: [
                "com.test.app": "Test Profile",
                "com.test.app.extension": "Test Extension Profile"
            ]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "TestApp",
            configuration: "Release",
            output: "TestApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "test@example.com",
            signing: signingConfig
        )

        // When/Then - Verify the struct properly holds the values
        #expect(releaseConfig.signing?.signingCertificate == "iPhone Distribution")
        #expect(releaseConfig.signing?.teamID == "ABC123")
        #expect(releaseConfig.signing?.signingStyle == "manual")
        #expect(releaseConfig.signing?.provisioningProfiles?.count == 2)
        #expect(releaseConfig.signing?.provisioningProfiles?["com.test.app"] == "Test Profile")
        #expect(releaseConfig.signing?.provisioningProfiles?["com.test.app.extension"] == "Test Extension Profile")
    }
}
