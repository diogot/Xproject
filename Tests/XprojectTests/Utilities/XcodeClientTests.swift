//
// XcodeClientTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("XcodeClient Tests", .tags(.xcodeClient))
struct XcodeClientTests {
    @Test("XcodeClient can be instantiated")
    func testXcodeClientInstantiation() throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockConfigProvider = MockConfigurationProvider(
            config: XprojectConfiguration(
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
            commandExecutor: mockExecutor,
            verbose: false
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
        let config = XprojectConfiguration(
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
            commandExecutor: mockExecutor,
            verbose: false
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
        let config = XprojectConfiguration(
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
            commandExecutor: mockExecutor,
            verbose: false
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
        let config = XprojectConfiguration(
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
            commandExecutor: mockExecutor,
            verbose: false
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

    @Test("XcodeClient handles Xcode version fetch failure when command fails")
    func testXcodeVersionFetchFailureOnCommandFailure() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Configure mock to fail mdfind and find commands (Xcode discovery)
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse.failure
        )

        // Mock configuration with specific Xcode version
        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "15.0",
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
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // When/Then - Try to build which will trigger Xcode version discovery
        do {
            try await xcodeClient.buildForTesting(
                scheme: "TestScheme",
                clean: false,
                buildDestination: "generic/platform=iOS Simulator"
            )
            Issue.record("Should have thrown an error")
        } catch XcodeClientError.xcodeVersionNotFound {
            // Expected error when no Xcode installation is found
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("XcodeClient handles Xcode version fetch failure when PlistBuddy fails")
    func testXcodeVersionFetchFailureOnPlistBuddyFailure() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Configure mock to return fake Xcode path but fail PlistBuddy command
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )

        // Make PlistBuddy command fail - this will be caught by try? and result in xcodeVersionNotFound
        mockExecutor.setDefaultResponse(MockCommandExecutor.MockResponse.failure)

        // Mock configuration with specific Xcode version
        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "15.0",
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
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // When/Then - Try to build which will trigger Xcode version fetch
        // Since fetchXcodeVersion fails and is caught by try?, no matching Xcode will be found
        do {
            try await xcodeClient.buildForTesting(
                scheme: "TestScheme",
                clean: false,
                buildDestination: "generic/platform=iOS Simulator"
            )
            Issue.record("Should have thrown an error")
        } catch XcodeClientError.xcodeVersionNotFound {
            // Expected error when PlistBuddy fails - no version can be read so no matching Xcode found
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("XcodeClient handles Xcode version fetch failure when PlistBuddy returns empty output")
    func testXcodeVersionFetchFailureOnEmptyOutput() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Configure mock to return fake Xcode path and empty PlistBuddy output
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )

        // Make PlistBuddy command return empty output - this will cause fetchXcodeVersion to throw
        // which is caught by try? and results in xcodeVersionNotFound
        mockExecutor.setDefaultResponse(MockCommandExecutor.MockResponse(exitCode: 0, output: ""))

        // Mock configuration with specific Xcode version
        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "15.0",
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
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // When/Then - Try to build which will trigger Xcode version fetch
        // Since fetchXcodeVersion throws due to empty output and is caught by try?, no matching Xcode will be found
        do {
            try await xcodeClient.buildForTesting(
                scheme: "TestScheme",
                clean: false,
                buildDestination: "generic/platform=iOS Simulator"
            )
            Issue.record("Should have thrown an error")
        } catch XcodeClientError.xcodeVersionNotFound {
            // Expected error when PlistBuddy returns empty output - no version can be read so no matching Xcode found
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("XcodeClient upload handles version fetch failure through getXcodeVersion")
    func testUploadHandlesVersionFetchFailure() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Configure successful Xcode discovery but failing version fetch
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )

        // Make PlistBuddy command fail - this gets caught by try? in getXcodeVersion
        mockExecutor.setDefaultResponse(MockCommandExecutor.MockResponse.failure)

        // Mock configuration with specific Xcode version and release config
        let releaseConfig = ReleaseConfiguration(
            scheme: "TestApp",
            configuration: "Release",
            output: "TestApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "test@example.com",
            signing: nil
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "15.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // When/Then - Try upload which calls getXcodeVersion
        // Since fetchXcodeVersion fails and is caught by try?, no matching Xcode will be found
        do {
            try await xcodeClient.upload(environment: "production")
            Issue.record("Should have thrown an error")
        } catch XcodeClientError.xcodeVersionNotFound {
            // Expected error when version fetch fails - results in no matching Xcode being found
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
