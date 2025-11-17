//
// VersionTests.swift
// XprojectTests
//

import Testing
@testable import Xproject

// MARK: - Initialization Tests

@Test
func initWithIntegers() {
    let version = Version(major: 1, minor: 2, patch: 3)
    #expect(version.major == 1)
    #expect(version.minor == 2)
    #expect(version.patch == 3)
}

@Test
func initWithIntegersDefaultPatch() {
    let version = Version(major: 1, minor: 2)
    #expect(version.major == 1)
    #expect(version.minor == 2)
    #expect(version.patch == 0)
}

// MARK: - String Parsing Tests

@Test
func parseValidVersionWithPatch() throws {
    let version = try Version(string: "1.2.3")
    #expect(version.major == 1)
    #expect(version.minor == 2)
    #expect(version.patch == 3)
}

@Test
func parseValidVersionWithoutPatch() throws {
    let version = try Version(string: "1.2")
    #expect(version.major == 1)
    #expect(version.minor == 2)
    #expect(version.patch == 0)
}

@Test
func parseInvalidFormatTooFewComponents() {
    var caughtError: VersionError?
    do {
        _ = try Version(string: "1")
    } catch let error as VersionError {
        caughtError = error
    } catch {
        #expect(Bool(false), "Unexpected error type")
    }

    guard let error = caughtError, case .invalidFormat("1") = error else {
        #expect(Bool(false), "Expected VersionError.invalidFormat(\"1\")")
        return
    }
}

@Test
func parseInvalidFormatTooManyComponents() {
    var caughtError: VersionError?
    do {
        _ = try Version(string: "1.2.3.4")
    } catch let error as VersionError {
        caughtError = error
    } catch {
        #expect(Bool(false), "Unexpected error type")
    }

    guard let error = caughtError, case .invalidFormat("1.2.3.4") = error else {
        #expect(Bool(false), "Expected VersionError.invalidFormat(\"1.2.3.4\")")
        return
    }
}

@Test
func parseInvalidFormatNonNumeric() {
    var caughtError: VersionError?
    do {
        _ = try Version(string: "1.2.x")
    } catch let error as VersionError {
        caughtError = error
    } catch {
        #expect(Bool(false), "Unexpected error type")
    }

    guard let error = caughtError, case .invalidFormat("1.2.x") = error else {
        #expect(Bool(false), "Expected VersionError.invalidFormat(\"1.2.x\")")
        return
    }
}

@Test
func parseInvalidFormatNonNumericMajor() {
    var caughtError: VersionError?
    do {
        _ = try Version(string: "a.2.3")
    } catch let error as VersionError {
        caughtError = error
    } catch {
        #expect(Bool(false), "Unexpected error type")
    }

    guard let error = caughtError, case .invalidFormat("a.2.3") = error else {
        #expect(Bool(false), "Expected VersionError.invalidFormat(\"a.2.3\")")
        return
    }
}

// MARK: - Bump Tests

@Test
func bumpPatch() {
    let version = Version(major: 1, minor: 2, patch: 3)
    let bumped = version.bumped(.patch)
    #expect(bumped.major == 1)
    #expect(bumped.minor == 2)
    #expect(bumped.patch == 4)
}

@Test
func bumpMinor() {
    let version = Version(major: 1, minor: 2, patch: 3)
    let bumped = version.bumped(.minor)
    #expect(bumped.major == 1)
    #expect(bumped.minor == 3)
    #expect(bumped.patch == 0)
}

@Test
func bumpMajor() {
    let version = Version(major: 1, minor: 2, patch: 3)
    let bumped = version.bumped(.major)
    #expect(bumped.major == 2)
    #expect(bumped.minor == 0)
    #expect(bumped.patch == 0)
}

@Test
func bumpPatchFromZero() {
    let version = Version(major: 1, minor: 0, patch: 0)
    let bumped = version.bumped(.patch)
    #expect(bumped == Version(major: 1, minor: 0, patch: 1))
}

@Test
func bumpMinorFromZero() {
    let version = Version(major: 1, minor: 0, patch: 0)
    let bumped = version.bumped(.minor)
    #expect(bumped == Version(major: 1, minor: 1, patch: 0))
}

@Test
func bumpMajorFromZero() {
    let version = Version(major: 1, minor: 0, patch: 0)
    let bumped = version.bumped(.major)
    #expect(bumped == Version(major: 2, minor: 0, patch: 0))
}

// MARK: - String Representation Tests

@Test
func descriptionString() {
    let version = Version(major: 1, minor: 2, patch: 3)
    #expect(version.description == "1.2.3")
}

@Test
func descriptionWithZeroPatch() {
    let version = Version(major: 1, minor: 2, patch: 0)
    #expect(version.description == "1.2.0")
}

@Test
func fullVersionWithBuild() {
    let version = Version(major: 1, minor: 2, patch: 3)
    #expect(version.fullVersion(build: 456) == "1.2.3-456")
}

// MARK: - Equality Tests

@Test
func equality() {
    let version1 = Version(major: 1, minor: 2, patch: 3)
    let version2 = Version(major: 1, minor: 2, patch: 3)
    #expect(version1 == version2)
}

@Test
func inequality() {
    let version1 = Version(major: 1, minor: 2, patch: 3)
    let version2 = Version(major: 1, minor: 2, patch: 4)
    #expect(version1 != version2)
}
