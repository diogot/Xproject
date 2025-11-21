//
// AppKeysTemplateTests.swift
// XprojectTests
//
// Tests for AppKeysTemplate
//

import Foundation
import Testing
@testable import Xproject

@Suite("AppKeysTemplate Tests")
struct AppKeysTemplateTests {
    @Test("Generate AppKeys with basic secrets")
    func testGenerateBasicAppKeys() throws {
        // Given
        let secrets = [
            "all_api_key": "secret_key_123",
            "all_database_password": "super_secret_password"
        ]
        let prefixes = ["all"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then
        #expect(generated.contains("public final class AppKeys"))
        #expect(generated.contains("private static let _apiKey: [UInt8]"))
        #expect(generated.contains("private static let _databasePassword: [UInt8]"))
        #expect(generated.contains("public static var apiKey: String"))
        #expect(generated.contains("public static var databasePassword: String"))
        #expect(generated.contains("var deobfuscated: [UInt8]"))

        // Should NOT contain plaintext secrets
        #expect(!generated.contains("secret_key_123"))
        #expect(!generated.contains("super_secret_password"))
    }

    @Test("Filter secrets by prefix")
    func testPrefixFiltering() throws {
        // Given
        let secrets = [
            "all_shared_key": "shared_secret",
            "ios_app_key": "ios_secret",
            "tvos_app_key": "tvos_secret",
            "services_api_key": "services_secret"
        ]

        // When - filter for iOS only
        let iosGenerated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: ["all", "ios"],
            environment: "dev"
        )

        // Then
        #expect(iosGenerated.contains("_sharedKey")) // all_ prefix
        #expect(iosGenerated.contains("_appKey")) // ios_ prefix
        #expect(!iosGenerated.contains("tvos")) // tvos_ excluded
        #expect(!iosGenerated.contains("services")) // services_ excluded
    }

    @Test("Convert property names to camelCase")
    func testPropertyNameConversion() throws {
        // Given
        let secrets = [
            "all_api_key": "value1",
            "ios_shopify_api_key": "value2",
            "all_database_connection_url": "value3",
            "services_mux_api_token": "value4"
        ]
        let prefixes = ["all", "ios", "services"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then - check camelCase conversion
        #expect(generated.contains("public static var apiKey: String"))
        #expect(generated.contains("public static var shopifyAPIKey: String")) // API uppercase
        #expect(generated.contains("public static var databaseConnectionURL: String")) // URL suffix capitalized
        #expect(generated.contains("public static var muxAPIToken: String")) // API capitalized
    }

    @Test("Handle URL and API suffixes correctly")
    func testURLAndAPISuffixes() throws {
        // Given
        let secrets = [
            "all_api_url": "https://api.example.com",
            "all_base_uri": "https://base.example.com",
            "all_shopify_api_key": "key123"
        ]
        let prefixes = ["all"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then
        #expect(generated.contains("public static var apiURL: String")) // URL uppercase
        #expect(generated.contains("public static var baseURI: String")) // URI uppercase
        #expect(generated.contains("public static var shopifyAPIKey: String")) // API uppercase
    }

    @Test("Generated code includes deobfuscation extension")
    func testDeobfuscationExtensionIncluded() throws {
        // Given
        let secrets = ["all_key": "value"]
        let prefixes = ["all"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then
        #expect(generated.contains("private extension Array where Element == UInt8"))
        #expect(generated.contains("var deobfuscated: [UInt8]"))
        #expect(generated.contains("let halfCount = count / 2"))
        #expect(generated.contains("zip(xoredHalf, keyHalf).map(^)"))
    }

    @Test("Handle empty secrets")
    func testEmptySecrets() throws {
        // Given
        let secrets: [String: String] = [:]
        let prefixes = ["all"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then - should still generate valid class structure
        #expect(generated.contains("public final class AppKeys"))
        #expect(generated.contains("private init()"))
        #expect(generated.contains("var deobfuscated: [UInt8]"))
    }

    @Test("Handle secrets with no matching prefixes")
    func testNoMatchingPrefixes() throws {
        // Given
        let secrets = [
            "android_key": "android_secret",
            "web_key": "web_secret"
        ]
        let prefixes = ["ios", "tvos"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then - should generate empty class (no properties)
        #expect(generated.contains("public final class AppKeys"))
        #expect(!generated.contains("android"))
        #expect(!generated.contains("web"))
    }

    @Test("Multiple prefixes work correctly")
    func testMultiplePrefixes() throws {
        // Given
        let secrets = [
            "all_shared": "shared_value",
            "ios_specific": "ios_value",
            "tvos_specific": "tvos_value",
            "android_specific": "android_value"
        ]
        let prefixes = ["all", "ios", "tvos"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then
        #expect(generated.contains("_shared")) // all_ prefix
        #expect(generated.contains("_specific")) // ios_ and tvos_ prefix (same property name after prefix removal)
        #expect(!generated.contains("android"))
    }

    @Test("Generated code structure is correct")
    func testGeneratedCodeStructure() throws {
        // Given
        let secrets = ["all_test_key": "test_value"]
        let prefixes = ["all"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then - verify structure
        #expect(generated.contains("// Generated by xp secrets generate dev"))
        #expect(generated.contains("DO NOT EDIT"))
        #expect(generated.contains("import Foundation"))
        #expect(generated.contains("/// Application secrets (obfuscated)"))
        #expect(generated.contains("public final class AppKeys {"))
        #expect(generated.contains("private init() {}"))
        #expect(generated.contains("// MARK: - Obfuscated Storage"))
        #expect(generated.contains("// MARK: - Public Accessors"))
        #expect(generated.contains("// MARK: - Deobfuscation"))
    }

    @Test("Byte array formatting is readable")
    func testByteArrayFormatting() throws {
        // Given - create a secret that will generate a long byte array
        let longSecret = String(repeating: "a", count: 100)
        let secrets = ["all_long_key": longSecret]
        let prefixes = ["all"]

        // When
        let generated = AppKeysTemplate.generateAppKeys(
            secrets: secrets,
            prefixes: prefixes,
            environment: "dev"
        )

        // Then - should have line breaks for readability
        #expect(generated.contains("[UInt8] = ["))
        #expect(generated.contains("]")) // Array closing bracket

        // Count newlines in the byte array section (should have some for long arrays)
        let lines = generated.components(separatedBy: "\n")
        let byteArrayLines = lines.filter { $0.contains("[UInt8] = [") || $0.contains("        ") }
        #expect(byteArrayLines.count > 1) // Should wrap to multiple lines
    }
}
