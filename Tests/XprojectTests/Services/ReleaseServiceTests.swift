//
// ReleaseServiceTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("ReleaseService Tests", .tags(.releaseService))
struct ReleaseServiceTests {
    // MARK: - Helper Methods

    private func createReleaseConfiguration() -> XprojectConfiguration {
        let releaseConfig = [
            "production-ios": ReleaseConfiguration(
                scheme: "Nebula",
                configuration: "Release",
                output: "Nebula",
                destination: "iOS",
                type: "ios",
                appStoreAccount: "test@example.com",
                signing: SigningConfiguration(
                    signingCertificate: "iPhone Distribution",
                    teamID: "ABC123",
                    signingStyle: "manual",
                    provisioningProfiles: [
                        "com.example.app": "Distribution Profile"
                    ]
                )
            ),
            "dev-ios": ReleaseConfiguration(
                scheme: "Nebula",
                configuration: "Debug",
                output: "Nebula-Dev",
                destination: "iOS",
                type: "ios",
                appStoreAccount: "test@example.com",
                signing: nil
            )
        ]

        return XprojectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: releaseConfig
            ),
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )
    }

    // MARK: - Instantiation Tests

    @Test("ReleaseService can be instantiated")
    func releaseServiceInstantiation() throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let mockConfigProvider = MockConfigurationProvider(config: createReleaseConfiguration())

        // When
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // Then
        #expect(type(of: releaseService) == ReleaseService.self)
    }

    // MARK: - Full Release Tests

    @Test("ReleaseService performs full release workflow")
    func testFullReleaseWorkflow() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "production-ios")

        // Then
        #expect(results.environment == "production-ios")
        #expect(results.scheme == "Nebula")
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == true)
        #expect(results.uploadSucceeded == true)
        #expect(results.hasFailures == false)
        #expect(results.isComplete == true)

        let archiveCalls = await mockXcodeClient.archiveCalls
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls

        #expect(archiveCalls.count == 1)
        #expect(archiveCalls[0].environment == "production-ios")
        #expect(ipaCalls.count == 1)
        #expect(ipaCalls[0].environment == "production-ios")
        #expect(uploadCalls.count == 1)
        #expect(uploadCalls[0].environment == "production-ios")
    }

    // MARK: - Archive Only Tests

    @Test("ReleaseService performs archive-only workflow")
    func testArchiveOnlyWorkflow() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(
            environment: "production-ios",
            archiveOnly: true
        )

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == nil)
        #expect(results.uploadSucceeded == nil)
        #expect(results.hasFailures == false)
        #expect(results.isComplete == true)

        let archiveCalls = await mockXcodeClient.archiveCalls
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls

        #expect(archiveCalls.count == 1)
        #expect(ipaCalls.isEmpty)
        #expect(uploadCalls.isEmpty)
    }

    // MARK: - Skip Upload Tests

    @Test("ReleaseService performs release without upload")
    func testSkipUploadWorkflow() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(
            environment: "production-ios",
            skipUpload: true
        )

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == true)
        #expect(results.uploadSucceeded == nil)
        #expect(results.hasFailures == false)
        #expect(results.isComplete == true)

        let archiveCalls = await mockXcodeClient.archiveCalls
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls

        #expect(archiveCalls.count == 1)
        #expect(ipaCalls.count == 1)
        #expect(uploadCalls.isEmpty)
    }

    // MARK: - Upload Only Tests

    @Test("ReleaseService performs upload-only workflow")
    func testUploadOnlyWorkflow() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(
            environment: "production-ios",
            uploadOnly: true
        )

        // Then
        #expect(results.archiveSucceeded == nil)
        #expect(results.ipaSucceeded == nil)
        #expect(results.uploadSucceeded == true)
        #expect(results.hasFailures == false)
        #expect(results.isComplete == true)

        let archiveCalls = await mockXcodeClient.archiveCalls
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls

        #expect(archiveCalls.isEmpty)
        #expect(ipaCalls.isEmpty)
        #expect(uploadCalls.count == 1)
    }

    // MARK: - Error Handling Tests

    @Test("ReleaseService handles archive failure")
    func testArchiveFailure() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        await mockXcodeClient.setShouldFailArchiveForEnvironment("production-ios", shouldFail: true)
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "production-ios")

        // Then
        #expect(results.archiveSucceeded == false)
        #expect(results.archiveError != nil)
        #expect(results.ipaSucceeded == nil)
        #expect(results.uploadSucceeded == nil)
        #expect(results.hasFailures == true)
        #expect(results.isComplete == false)

        // Should not proceed to IPA/upload after archive failure
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls
        #expect(ipaCalls.isEmpty)
        #expect(uploadCalls.isEmpty)
    }

    @Test("ReleaseService handles IPA generation failure")
    func testIPAFailure() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        await mockXcodeClient.setShouldFailIPAForEnvironment("production-ios", shouldFail: true)
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "production-ios")

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == false)
        #expect(results.ipaError != nil)
        #expect(results.uploadSucceeded == nil)
        #expect(results.hasFailures == true)
        #expect(results.isComplete == false)

        // Should not proceed to upload after IPA failure
        let uploadCalls = await mockXcodeClient.uploadCalls
        #expect(uploadCalls.isEmpty)
    }

    @Test("ReleaseService handles upload failure")
    func testUploadFailure() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        await mockXcodeClient.setShouldFailUploadForEnvironment("production-ios", shouldFail: true)
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "production-ios")

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == true)
        #expect(results.uploadSucceeded == false)
        #expect(results.uploadError != nil)
        #expect(results.hasFailures == true)
        #expect(results.isComplete == false)
    }

    @Test("ReleaseService throws error for unknown environment")
    func testUnknownEnvironmentError() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = createReleaseConfiguration()
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When/Then
        do {
            _ = try await releaseService.createRelease(environment: "unknown-env")
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as ReleaseError {
            switch error {
            case let .environmentNotFound(environment, available):
                #expect(environment == "unknown-env")
                #expect(available.contains("production-ios"))
                #expect(available.contains("dev-ios"))
            default:
                #expect(Bool(false), "Wrong ReleaseError type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("ReleaseService throws error when no xcode configuration")
    func testNoXcodeConfigurationError() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()
        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["test": "Test.xcodeproj"],
            setup: nil,
            xcode: nil,
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )
        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When/Then
        do {
            _ = try await releaseService.createRelease(environment: "production-ios")
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as ReleaseError {
            switch error {
            case .noXcodeConfiguration:
                // Success
                break
            default:
                #expect(Bool(false), "Wrong ReleaseError type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    // MARK: - Signing Configuration Integration Tests

    @Test("ReleaseService handles automatic signing configuration")
    func testAutomaticSigningIntegration() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()

        let automaticSigning = SigningConfiguration(
            signingCertificate: nil,
            teamID: "ABC123",
            signingStyle: "automatic",
            provisioningProfiles: nil
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "Nebula",
            configuration: "Debug",
            output: "Nebula-Dev",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: automaticSigning
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: ["dev-ios": releaseConfig]
            ),
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "dev-ios")

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == true)
        #expect(results.uploadSucceeded == true)
        #expect(results.hasFailures == false)

        let archiveCalls = await mockXcodeClient.archiveCalls
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls

        #expect(archiveCalls.count == 1)
        #expect(archiveCalls[0].environment == "dev-ios")
        #expect(ipaCalls.count == 1)
        #expect(uploadCalls.count == 1)
    }

    @Test("ReleaseService handles manual signing configuration")
    func testManualSigningIntegration() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()

        let manualSigning = SigningConfiguration(
            signingCertificate: "iPhone Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: [
                "com.example.app": "Distribution Profile",
                "com.example.app.extension": "Extension Profile"
            ]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "Nebula",
            configuration: "Release",
            output: "Nebula",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "team@example.com",
            signing: manualSigning
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: "TestApp.xcworkspace",
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: ["production-ios": releaseConfig]
            ),
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "production-ios")

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == true)
        #expect(results.uploadSucceeded == true)
        #expect(results.hasFailures == false)

        let archiveCalls = await mockXcodeClient.archiveCalls
        let ipaCalls = await mockXcodeClient.generateIPACalls
        let uploadCalls = await mockXcodeClient.uploadCalls

        #expect(archiveCalls.count == 1)
        #expect(ipaCalls.count == 1)
        #expect(uploadCalls.count == 1)
    }

    @Test("ReleaseService handles tvOS release configuration")
    func testTVOSReleaseConfiguration() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()

        let tvOSSigning = SigningConfiguration(
            signingCertificate: "Apple Distribution",
            teamID: "ABC123",
            signingStyle: "manual",
            provisioningProfiles: ["com.example.app.tv": "tvOS Profile"]
        )

        let releaseConfig = ReleaseConfiguration(
            scheme: "MyAppTV",
            configuration: "Release",
            output: "MyAppTV",
            destination: "tvOS",
            type: "appletvos",
            appStoreAccount: "team@example.com",
            signing: tvOSSigning
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["tvos": "TV/TV.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: ["production-tvos": releaseConfig]
            ),
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When
        let results = try await releaseService.createRelease(environment: "production-tvos")

        // Then
        #expect(results.environment == "production-tvos")
        #expect(results.scheme == "MyAppTV")
        #expect(results.archiveSucceeded == true)
        #expect(results.ipaSucceeded == true)
        #expect(results.uploadSucceeded == true)
    }

    @Test("ReleaseService handles multiple environments sequentially")
    func testMultipleEnvironmentsSequential() async throws {
        // Given
        let mockXcodeClient = MockXcodeClient()

        let devConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Debug",
            output: "MyApp-Dev",
            destination: "iOS",
            type: "ios",
            appStoreAccount: nil,
            signing: nil
        )

        let prodConfig = ReleaseConfiguration(
            scheme: "MyApp",
            configuration: "Release",
            output: "MyApp",
            destination: "iOS",
            type: "ios",
            appStoreAccount: "team@example.com",
            signing: SigningConfiguration(
                signingCertificate: "iPhone Distribution",
                teamID: "ABC123",
                signingStyle: "manual",
                provisioningProfiles: ["com.example.app": "Profile"]
            )
        )

        let config = XprojectConfiguration(
            appName: "TestApp",
            workspacePath: nil,
            projectPaths: ["ios": "TestApp.xcodeproj"],
            setup: nil,
            xcode: XcodeConfiguration(
                version: "16.0",
                buildPath: "build",
                reportsPath: "reports",
                tests: nil,
                release: [
                    "dev-ios": devConfig,
                    "production-ios": prodConfig
                ]
            ),
            version: nil,
            secrets: nil,
            provision: nil,
            prReport: nil
        )

        let mockConfigProvider = MockConfigurationProvider(config: config)
        let releaseService = ReleaseService(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            configurationProvider: mockConfigProvider,
            xcodeClient: mockXcodeClient
        )

        // When - Release dev first
        let devResults = try await releaseService.createRelease(environment: "dev-ios")

        // Then
        #expect(devResults.environment == "dev-ios")
        #expect(devResults.scheme == "MyApp")
        #expect(devResults.archiveSucceeded == true)

        // When - Release production
        let prodResults = try await releaseService.createRelease(environment: "production-ios")

        // Then
        #expect(prodResults.environment == "production-ios")
        #expect(prodResults.scheme == "MyApp")
        #expect(prodResults.archiveSucceeded == true)

        // Verify both were called
        let archiveCalls = await mockXcodeClient.archiveCalls
        #expect(archiveCalls.count == 2)
        #expect(archiveCalls[0].environment == "dev-ios")
        #expect(archiveCalls[1].environment == "production-ios")
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var releaseService: Self
}
