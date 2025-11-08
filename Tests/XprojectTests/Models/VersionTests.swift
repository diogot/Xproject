//
// VersionTests.swift
// XprojectTests
//

import XCTest
@testable import Xproject

final class VersionTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithIntegers() {
        let version = Version(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
    }

    func testInitWithIntegersDefaultPatch() {
        let version = Version(major: 1, minor: 2)
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 0)
    }

    // MARK: - String Parsing Tests

    func testParseValidVersionWithPatch() throws {
        let version = try Version(string: "1.2.3")
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
    }

    func testParseValidVersionWithoutPatch() throws {
        let version = try Version(string: "1.2")
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 0)
    }

    func testParseInvalidFormatTooFewComponents() {
        XCTAssertThrowsError(try Version(string: "1")) { error in
            guard case VersionError.invalidFormat("1") = error else {
                XCTFail("Expected invalidFormat error")
                return
            }
        }
    }

    func testParseInvalidFormatTooManyComponents() {
        XCTAssertThrowsError(try Version(string: "1.2.3.4")) { error in
            guard case VersionError.invalidFormat("1.2.3.4") = error else {
                XCTFail("Expected invalidFormat error")
                return
            }
        }
    }

    func testParseInvalidFormatNonNumeric() {
        XCTAssertThrowsError(try Version(string: "1.2.x")) { error in
            guard case VersionError.invalidFormat("1.2.x") = error else {
                XCTFail("Expected invalidFormat error")
                return
            }
        }
    }

    func testParseInvalidFormatNonNumericMajor() {
        XCTAssertThrowsError(try Version(string: "a.2.3")) { error in
            guard case VersionError.invalidFormat("a.2.3") = error else {
                XCTFail("Expected invalidFormat error")
                return
            }
        }
    }

    // MARK: - Bump Tests

    func testBumpPatch() {
        let version = Version(major: 1, minor: 2, patch: 3)
        let bumped = version.bumped(.patch)
        XCTAssertEqual(bumped.major, 1)
        XCTAssertEqual(bumped.minor, 2)
        XCTAssertEqual(bumped.patch, 4)
    }

    func testBumpMinor() {
        let version = Version(major: 1, minor: 2, patch: 3)
        let bumped = version.bumped(.minor)
        XCTAssertEqual(bumped.major, 1)
        XCTAssertEqual(bumped.minor, 3)
        XCTAssertEqual(bumped.patch, 0)
    }

    func testBumpMajor() {
        let version = Version(major: 1, minor: 2, patch: 3)
        let bumped = version.bumped(.major)
        XCTAssertEqual(bumped.major, 2)
        XCTAssertEqual(bumped.minor, 0)
        XCTAssertEqual(bumped.patch, 0)
    }

    func testBumpPatchFromZero() {
        let version = Version(major: 1, minor: 0, patch: 0)
        let bumped = version.bumped(.patch)
        XCTAssertEqual(bumped, Version(major: 1, minor: 0, patch: 1))
    }

    func testBumpMinorFromZero() {
        let version = Version(major: 1, minor: 0, patch: 0)
        let bumped = version.bumped(.minor)
        XCTAssertEqual(bumped, Version(major: 1, minor: 1, patch: 0))
    }

    func testBumpMajorFromZero() {
        let version = Version(major: 1, minor: 0, patch: 0)
        let bumped = version.bumped(.major)
        XCTAssertEqual(bumped, Version(major: 2, minor: 0, patch: 0))
    }

    // MARK: - String Representation Tests

    func testDescription() {
        let version = Version(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(version.description, "1.2.3")
    }

    func testDescriptionWithZeroPatch() {
        let version = Version(major: 1, minor: 2, patch: 0)
        XCTAssertEqual(version.description, "1.2.0")
    }

    func testFullVersionWithBuild() {
        let version = Version(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(version.fullVersion(build: 456), "1.2.3-456")
    }

    // MARK: - Equality Tests

    func testEquality() {
        let version1 = Version(major: 1, minor: 2, patch: 3)
        let version2 = Version(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(version1, version2)
    }

    func testInequality() {
        let version1 = Version(major: 1, minor: 2, patch: 3)
        let version2 = Version(major: 1, minor: 2, patch: 4)
        XCTAssertNotEqual(version1, version2)
    }
}
