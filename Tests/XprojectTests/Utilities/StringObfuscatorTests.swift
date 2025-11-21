//
// StringObfuscatorTests.swift
// XprojectTests
//
// Tests for string obfuscation and deobfuscation
//

import Foundation
import Testing
@testable import Xproject

@Suite("StringObfuscator Tests")
struct StringObfuscatorTests {
    // MARK: - Round-trip tests

    @Test("Obfuscate and deobfuscate simple ASCII string")
    func testSimpleASCIIRoundTrip() throws {
        // Given
        let original = "Hello, World!"

        // When
        let obfuscated = StringObfuscator.obfuscate(original)
        let deobfuscated = obfuscated.deobfuscated
        let result = String(bytes: deobfuscated, encoding: .utf8)

        // Then
        #expect(result == original)
    }

    @Test("Obfuscate and deobfuscate API key")
    func testAPIKeyRoundTrip() throws {
        // Given
        let apiKey = "sk_live_1234567890abcdef"

        // When
        let obfuscated = StringObfuscator.obfuscate(apiKey)
        let deobfuscated = obfuscated.deobfuscated
        let result = String(bytes: deobfuscated, encoding: .utf8)

        // Then
        #expect(result == apiKey)
    }

    @Test("Obfuscate and deobfuscate Unicode string")
    func testUnicodeRoundTrip() throws {
        // Given
        let original = "Hello 世界 🌍 Ñoño"

        // When
        let obfuscated = StringObfuscator.obfuscate(original)
        let deobfuscated = obfuscated.deobfuscated
        let result = String(bytes: deobfuscated, encoding: .utf8)

        // Then
        #expect(result == original)
    }

    @Test("Obfuscate and deobfuscate empty string")
    func testEmptyStringRoundTrip() throws {
        // Given
        let original = ""

        // When
        let obfuscated = StringObfuscator.obfuscate(original)
        let deobfuscated = obfuscated.deobfuscated
        let result = String(bytes: deobfuscated, encoding: .utf8)

        // Then
        #expect(result == original)
    }

    @Test("Obfuscate and deobfuscate long string")
    func testLongStringRoundTrip() throws {
        // Given
        let original = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 100)

        // When
        let obfuscated = StringObfuscator.obfuscate(original)
        let deobfuscated = obfuscated.deobfuscated
        let result = String(bytes: deobfuscated, encoding: .utf8)

        // Then
        #expect(result == original)
    }

    // MARK: - Randomness tests

    @Test("Obfuscation produces different output each time")
    func testRandomness() throws {
        // Given
        let original = "sk_live_1234567890abcdef"

        // When
        let obfuscated1 = StringObfuscator.obfuscate(original)
        let obfuscated2 = StringObfuscator.obfuscate(original)

        // Then - the obfuscated arrays should be different (random)
        #expect(obfuscated1 != obfuscated2)

        // But they should both deobfuscate to the same original
        let result1 = String(bytes: obfuscated1.deobfuscated, encoding: .utf8)
        let result2 = String(bytes: obfuscated2.deobfuscated, encoding: .utf8)
        #expect(result1 == original)
        #expect(result2 == original)
    }

    // MARK: - Format tests

    @Test("Obfuscated array is twice the length of original")
    func testObfuscatedLength() throws {
        // Given
        let original = "sk_live_1234567890abcdef"
        let originalBytes = [UInt8](original.data(using: .utf8)!)

        // When
        let obfuscated = StringObfuscator.obfuscate(original)

        // Then
        #expect(obfuscated.count == originalBytes.count * 2)
    }

    @Test("Obfuscated array has even length")
    func testObfuscatedEvenLength() throws {
        // Given
        let strings = [
            "a",
            "ab",
            "abc",
            "abcd",
            "Hello, World!",
            "sk_live_1234567890abcdef"
        ]

        // When/Then
        for string in strings {
            let obfuscated = StringObfuscator.obfuscate(string)
            #expect(obfuscated.count % 2 == 0)
        }
    }

    @Test("Obfuscated bytes do not contain original string")
    func testNoPlaintextInObfuscated() throws {
        // Given
        let secret = "sk_live_1234567890abcdef"
        let obfuscated = StringObfuscator.obfuscate(secret)

        // When - convert obfuscated to string to simulate `strings` command
        let obfuscatedString = String(bytes: obfuscated, encoding: .utf8) ?? ""

        // Then - the secret should NOT appear in the obfuscated data
        #expect(!obfuscatedString.contains(secret))
    }

    // MARK: - Edge cases

    @Test("Deobfuscate empty array returns empty")
    func testDeobfuscateEmpty() throws {
        // Given
        let empty: [UInt8] = []

        // When
        let deobfuscated = empty.deobfuscated

        // Then
        #expect(deobfuscated.isEmpty)
    }

    @Test("Deobfuscate odd-length array returns empty")
    func testDeobfuscateOddLength() throws {
        // Given
        let oddLength: [UInt8] = [1, 2, 3]

        // When
        let deobfuscated = oddLength.deobfuscated

        // Then
        #expect(deobfuscated.isEmpty)
    }

    @Test("Obfuscate special characters")
    func testSpecialCharacters() throws {
        // Given
        let original = "!@#$%^&*()_+-={}[]|\\:;\"'<>,.?/~`"

        // When
        let obfuscated = StringObfuscator.obfuscate(original)
        let deobfuscated = obfuscated.deobfuscated
        let result = String(bytes: deobfuscated, encoding: .utf8)

        // Then
        #expect(result == original)
    }
}
