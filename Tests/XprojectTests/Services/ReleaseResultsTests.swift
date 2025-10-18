//
// ReleaseResultsTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("ReleaseResults Tests", .tags(.releaseResults))
struct ReleaseResultsTests {
    // MARK: - Test Error

    struct TestError: Error, Equatable {
        let message: String
    }

    // MARK: - Initialization Tests

    @Test("ReleaseResults initializes with correct environment and scheme")
    func testInitialization() {
        // When
        let results = ReleaseResults(environment: "production-ios", scheme: "MyApp")

        // Then
        #expect(results.environment == "production-ios")
        #expect(results.scheme == "MyApp")
        #expect(results.archiveSucceeded == nil)
        #expect(results.archiveError == nil)
        #expect(results.ipaSucceeded == nil)
        #expect(results.ipaError == nil)
        #expect(results.uploadSucceeded == nil)
        #expect(results.uploadError == nil)
    }

    @Test("ReleaseResults initializes with nil operation states")
    func testInitialOperationStates() {
        // When
        let results = ReleaseResults(environment: "dev-ios", scheme: "TestApp")

        // Then
        #expect(results.archiveSucceeded == nil)
        #expect(results.ipaSucceeded == nil)
        #expect(results.uploadSucceeded == nil)
        #expect(results.archiveError == nil)
        #expect(results.ipaError == nil)
        #expect(results.uploadError == nil)
    }

    // MARK: - Archive Recording Tests

    @Test("Recording archive success sets correct state")
    func testRecordArchiveSuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.archiveError == nil)
    }

    @Test("Recording archive failure sets correct state")
    func testRecordArchiveFailure() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Archive failed")

        // When
        results.recordArchiveFailure(error: error)

        // Then
        #expect(results.archiveSucceeded == false)
        #expect(results.archiveError != nil)
    }

    @Test("Recording archive success clears previous error")
    func testRecordArchiveSuccessClearsPreviousError() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Archive failed")
        results.recordArchiveFailure(error: error)

        // When
        results.recordArchiveSuccess()

        // Then
        #expect(results.archiveSucceeded == true)
        #expect(results.archiveError == nil)
    }

    // MARK: - IPA Recording Tests

    @Test("Recording IPA success sets correct state")
    func testRecordIPASuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordIPASuccess()

        // Then
        #expect(results.ipaSucceeded == true)
        #expect(results.ipaError == nil)
    }

    @Test("Recording IPA failure sets correct state")
    func testRecordIPAFailure() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "IPA generation failed")

        // When
        results.recordIPAFailure(error: error)

        // Then
        #expect(results.ipaSucceeded == false)
        #expect(results.ipaError != nil)
    }

    @Test("Recording IPA success clears previous error")
    func testRecordIPASuccessClearsPreviousError() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "IPA failed")
        results.recordIPAFailure(error: error)

        // When
        results.recordIPASuccess()

        // Then
        #expect(results.ipaSucceeded == true)
        #expect(results.ipaError == nil)
    }

    // MARK: - Upload Recording Tests

    @Test("Recording upload success sets correct state")
    func testRecordUploadSuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordUploadSuccess()

        // Then
        #expect(results.uploadSucceeded == true)
        #expect(results.uploadError == nil)
    }

    @Test("Recording upload failure sets correct state")
    func testRecordUploadFailure() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Upload failed")

        // When
        results.recordUploadFailure(error: error)

        // Then
        #expect(results.uploadSucceeded == false)
        #expect(results.uploadError != nil)
    }

    @Test("Recording upload success clears previous error")
    func testRecordUploadSuccessClearsPreviousError() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Upload failed")
        results.recordUploadFailure(error: error)

        // When
        results.recordUploadSuccess()

        // Then
        #expect(results.uploadSucceeded == true)
        #expect(results.uploadError == nil)
    }

    // MARK: - hasFailures Tests

    @Test("hasFailures is false when no operations attempted")
    func testHasFailuresWithNoOperations() {
        // Given
        let results = ReleaseResults(environment: "test", scheme: "Test")

        // Then
        #expect(results.hasFailures == false)
    }

    @Test("hasFailures is false when all operations succeed")
    func testHasFailuresAllSuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()
        results.recordUploadSuccess()

        // Then
        #expect(results.hasFailures == false)
    }

    @Test("hasFailures is true when archive fails")
    func testHasFailuresArchiveFailed() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Archive failed")

        // When
        results.recordArchiveFailure(error: error)

        // Then
        #expect(results.hasFailures == true)
    }

    @Test("hasFailures is true when IPA fails")
    func testHasFailuresIPAFailed() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "IPA failed")

        // When
        results.recordArchiveSuccess()
        results.recordIPAFailure(error: error)

        // Then
        #expect(results.hasFailures == true)
    }

    @Test("hasFailures is true when upload fails")
    func testHasFailuresUploadFailed() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Upload failed")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()
        results.recordUploadFailure(error: error)

        // Then
        #expect(results.hasFailures == true)
    }

    @Test("hasFailures is true when multiple operations fail")
    func testHasFailuresMultipleFailures() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let archiveError = TestError(message: "Archive failed")
        let ipaError = TestError(message: "IPA failed")

        // When
        results.recordArchiveFailure(error: archiveError)
        results.recordIPAFailure(error: ipaError)

        // Then
        #expect(results.hasFailures == true)
    }

    @Test("hasFailures is false when only successful operations recorded")
    func testHasFailuresPartialSuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When - Archive only (e.g., --archive-only mode)
        results.recordArchiveSuccess()

        // Then
        #expect(results.hasFailures == false)
    }

    // MARK: - isComplete Tests - No Operations

    @Test("isComplete is false when no operations attempted")
    func testIsCompleteNoOperations() {
        // Given
        let results = ReleaseResults(environment: "test", scheme: "Test")

        // Then
        #expect(results.isComplete == false)
    }

    // MARK: - isComplete Tests - Archive Only Scenarios

    @Test("isComplete is true for successful archive-only workflow")
    func testIsCompleteArchiveOnlySuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()

        // Then
        #expect(results.isComplete == true)
    }

    @Test("isComplete is false when archive fails")
    func testIsCompleteArchiveFailed() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Archive failed")

        // When
        results.recordArchiveFailure(error: error)

        // Then
        #expect(results.isComplete == false)
    }

    // MARK: - isComplete Tests - Archive + IPA Scenarios

    @Test("isComplete is true for successful archive and IPA workflow")
    func testIsCompleteArchiveAndIPASuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()

        // Then
        #expect(results.isComplete == true)
    }

    @Test("isComplete is false when IPA fails after successful archive")
    func testIsCompleteIPAFailedAfterArchive() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "IPA failed")

        // When
        results.recordArchiveSuccess()
        results.recordIPAFailure(error: error)

        // Then
        #expect(results.isComplete == false)
    }

    // MARK: - isComplete Tests - Full Workflow Scenarios

    @Test("isComplete is true for successful full workflow")
    func testIsCompleteFullWorkflowSuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()
        results.recordUploadSuccess()

        // Then
        #expect(results.isComplete == true)
    }

    @Test("isComplete is false when upload fails after successful archive and IPA")
    func testIsCompleteUploadFailedAfterArchiveAndIPA() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Upload failed")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()
        results.recordUploadFailure(error: error)

        // Then
        #expect(results.isComplete == false)
    }

    // MARK: - isComplete Tests - Upload Only Scenario

    @Test("isComplete is true for successful upload-only workflow")
    func testIsCompleteUploadOnlySuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordUploadSuccess()

        // Then
        #expect(results.isComplete == true)
    }

    @Test("isComplete is false for failed upload-only workflow")
    func testIsCompleteUploadOnlyFailed() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Upload failed")

        // When
        results.recordUploadFailure(error: error)

        // Then
        #expect(results.isComplete == false)
    }

    // MARK: - isComplete Tests - IPA Only Scenario

    @Test("isComplete is true for successful IPA-only workflow")
    func testIsCompleteIPAOnlySuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordIPASuccess()

        // Then
        #expect(results.isComplete == true)
    }

    @Test("isComplete is false for failed IPA-only workflow")
    func testIsCompleteIPAOnlyFailed() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "IPA failed")

        // When
        results.recordIPAFailure(error: error)

        // Then
        #expect(results.isComplete == false)
    }

    // MARK: - Combined Property Tests

    @Test("hasFailures and isComplete are consistent for full success")
    func testConsistencyFullSuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()
        results.recordUploadSuccess()

        // Then
        #expect(results.hasFailures == false)
        #expect(results.isComplete == true)
    }

    @Test("hasFailures and isComplete are consistent for partial failure")
    func testConsistencyPartialFailure() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")
        let error = TestError(message: "Upload failed")

        // When
        results.recordArchiveSuccess()
        results.recordIPASuccess()
        results.recordUploadFailure(error: error)

        // Then
        #expect(results.hasFailures == true)
        #expect(results.isComplete == false)
    }

    @Test("hasFailures and isComplete are consistent for archive-only success")
    func testConsistencyArchiveOnlySuccess() {
        // Given
        var results = ReleaseResults(environment: "test", scheme: "Test")

        // When
        results.recordArchiveSuccess()

        // Then
        #expect(results.hasFailures == false)
        #expect(results.isComplete == true)
    }

    @Test("hasFailures and isComplete are consistent for no operations")
    func testConsistencyNoOperations() {
        // Given
        let results = ReleaseResults(environment: "test", scheme: "Test")

        // Then
        #expect(results.hasFailures == false)
        #expect(results.isComplete == false)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var releaseResults: Self
}
