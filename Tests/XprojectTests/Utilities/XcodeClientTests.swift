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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
        // Note: Paths are now absolute (prepended with working directory)
        let workingDir = FileManager.default.temporaryDirectory.path
        let expectedBuildPath = URL(fileURLWithPath: workingDir).appendingPathComponent("custom-build").path
        let expectedReportsPath = URL(fileURLWithPath: workingDir).appendingPathComponent("custom-reports").path

        #expect(mockFileManager.createdDirectories.count == 2)
        #expect(mockFileManager.createdDirectories.contains(expectedBuildPath))
        #expect(mockFileManager.createdDirectories.contains(expectedReportsPath))
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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
            workingDirectory: FileManager.default.temporaryDirectory.path,
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

    // MARK: - Archive Tests

    @Test("archive command includes correct scheme and configuration")
    func testArchiveCommandStructure() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: ["production-ios": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.archive(environment: "production-ios")
        } catch {
            // Expected to fail on xcodebuild execution, we're just testing command structure
        }

        // Then
        let commands = mockExecutor.executedCommands
        let archiveCommand = commands.first { $0.command.contains("clean archive") }

        #expect(archiveCommand != nil)
        #expect(archiveCommand?.command.contains("-workspace 'TestApp.xcworkspace'") == true)
        #expect(archiveCommand?.command.contains("-configuration 'Release'") == true)
        #expect(archiveCommand?.command.contains("-scheme 'MyApp'") == true)
        #expect(archiveCommand?.command.contains("-destination 'generic/platform=iOS'") == true)
        #expect(archiveCommand?.command.contains("-archivePath 'build/MyApp.xcarchive'") == true)
        #expect(archiveCommand?.command.contains("-parallelizeTargets") == true)
    }

    @Test("archive uses correct output path for xcarchive")
    func testArchiveOutputPath() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: nil,
            output: "MyApp-Production",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "custom-build",
                reportsPath: "reports",
                tests: nil,
                release: ["staging": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.archive(environment: "staging")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let archiveCommand = commands.first { $0.command.contains("clean archive") }

        #expect(archiveCommand?.command.contains("-archivePath 'custom-build/MyApp-Production.xcarchive'") == true)
    }

    @Test("archive creates build directory before execution")
    func testArchiveCreatesDirectories() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Debug",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

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
                release: ["dev": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.archive(environment: "dev")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then - Verify directories were created with absolute paths
        #expect(mockFileManager.createdDirectories.contains("/test/project/build"))
        #expect(mockFileManager.createdDirectories.contains("/test/project/reports"))
    }

    @Test("archive without configuration omits configuration argument")
    func testArchiveWithoutConfiguration() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: nil,
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

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
                release: ["dev": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.archive(environment: "dev")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let archiveCommand = commands.first { $0.command.contains("clean archive") }

        #expect(archiveCommand != nil)
        #expect(archiveCommand?.command.contains("-configuration") == false)
    }

    // MARK: - Generate IPA Tests

    @Test("generateIPA command includes correct exportArchive arguments")
    func testGenerateIPACommandStructure() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Create temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let buildDir = tempDir.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

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
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: tempDir.path,
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.generateIPA(environment: "production")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let exportCommand = commands.first { $0.command.contains("-exportArchive") }

        #expect(exportCommand != nil)
        #expect(exportCommand?.command.contains("-exportArchive") == true)
        #expect(exportCommand?.command.contains("-archivePath 'build/MyApp.xcarchive'") == true)
        #expect(exportCommand?.command.contains("-exportPath 'build/MyApp-ipa'") == true)
        #expect(exportCommand?.command.contains("-exportOptionsPlist 'build/export.plist'") == true)
    }

    @Test("generateIPA with automatic signing includes allowProvisioningUpdates")
    func testGenerateIPAWithAutomaticSigning() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Create temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let buildDir = tempDir.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

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
                release: ["dev": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: tempDir.path,
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.generateIPA(environment: "dev")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let exportCommand = commands.first { $0.command.contains("-exportArchive") }

        #expect(exportCommand != nil)
        #expect(exportCommand?.command.contains("-allowProvisioningUpdates") == true)
    }

    @Test("generateIPA with manual signing does NOT include allowProvisioningUpdates")
    func testGenerateIPAWithManualSigning() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Create temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let buildDir = tempDir.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

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
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: tempDir.path,
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.generateIPA(environment: "production")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let exportCommand = commands.first { $0.command.contains("-exportArchive") }

        #expect(exportCommand != nil)
        #expect(exportCommand?.command.contains("-allowProvisioningUpdates") == false)
    }

    @Test("generateIPA cleans export directory before execution")
    func testGenerateIPACleansExportDirectory() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Create temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let buildDir = tempDir.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

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
                release: ["dev": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: tempDir.path,
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.generateIPA(environment: "dev")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let cleanCommand = commands.first { $0.command.contains("rm -rf") && $0.command.contains("build/MyApp-ipa") }

        #expect(cleanCommand != nil)
    }

    @Test("generateIPA uses custom build path for export")
    func testGenerateIPACustomBuildPath() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        // Create temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let buildDir = tempDir.appendingPathComponent("custom-output")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp-Staging",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "custom-output",
                reportsPath: "reports",
                tests: nil,
                release: ["staging": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: tempDir.path,
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.generateIPA(environment: "staging")
        } catch {
            // Expected to fail on xcodebuild execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let exportCommand = commands.first { $0.command.contains("-exportArchive") }

        #expect(exportCommand?.command.contains("-archivePath 'custom-output/MyApp-Staging.xcarchive'") == true)
        #expect(exportCommand?.command.contains("-exportPath 'custom-output/MyApp-Staging-ipa'") == true)
        #expect(exportCommand?.command.contains("-exportOptionsPlist 'custom-output/export.plist'") == true)
    }

    // MARK: - Upload Tests

    @Test("upload command uses correct IPA path")
    func testUploadCommandStructure() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

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
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.upload(environment: "production")
        } catch {
            // Expected to fail on altool execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let uploadCommand = commands.first { $0.command.contains("altool --upload-app") }

        #expect(uploadCommand != nil)
        #expect(uploadCommand?.command.contains("xcrun altool --upload-app") == true)
        #expect(uploadCommand?.command.contains("--type ios") == true)
        #expect(uploadCommand?.command.contains("-f 'build/MyApp-ipa/MyApp.ipa'") == true)
    }

    @Test("upload includes app_store_account when provided")
    func testUploadWithAppStoreAccount() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "developer@example.com",
            signing: nil
        )

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
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // When
        do {
            try await xcodeClient.upload(environment: "production")
        } catch {
            // Expected to fail on altool execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let uploadCommand = commands.first { $0.command.contains("altool --upload-app") }

        #expect(uploadCommand?.command.contains("-u developer@example.com") == true)
    }

    @Test("upload includes APP_STORE_PASS environment variable when set")
    func testUploadWithEnvironmentVariable() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "developer@example.com",
            signing: nil
        )

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
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "16.0")
        )

        // Set environment variable
        setenv("APP_STORE_PASS", "test_password", 1)
        defer { unsetenv("APP_STORE_PASS") }

        // When
        do {
            try await xcodeClient.upload(environment: "production")
        } catch {
            // Expected to fail on altool execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let uploadCommand = commands.first { $0.command.contains("altool --upload-app") }

        #expect(uploadCommand?.command.contains("-p @env:APP_STORE_PASS") == true)
    }

    @Test("upload uses correct Xcode version prefix")
    func testUploadUsesXcodeVersion() async throws {
        // Given
        let mockExecutor = MockCommandExecutor()
        let mockFileManager = MockFileManager()

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "15.4",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: ["production": releaseConfig]
            ),
            danger: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let xcodeClient = XcodeClient(
            workingDirectory: "/test/project",
            configurationProvider: mockConfigProvider,
            commandExecutor: mockExecutor,
            verbose: false
        ) { mockFileManager }

        // Mock Xcode discovery for version 15.4
        mockExecutor.setResponse(
            for: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "/Applications/Xcode.app")
        )
        mockExecutor.setResponse(
            for: "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"/Applications/Xcode.app/Contents/Info.plist\"",
            response: MockCommandExecutor.MockResponse(exitCode: 0, output: "15.4")
        )

        // When
        do {
            try await xcodeClient.upload(environment: "production")
        } catch {
            // Expected to fail on altool execution
        }

        // Then
        let commands = mockExecutor.executedCommands
        let uploadCommand = commands.first { $0.command.contains("altool --upload-app") }

        #expect(uploadCommand?.command.contains("DEVELOPER_DIR=\"/Applications/Xcode.app/Contents/Developer\"") == true)
    }
}
