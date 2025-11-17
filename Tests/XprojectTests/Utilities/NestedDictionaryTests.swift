//
// NestedDictionaryTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("NestedDictionary Tests")
struct NestedDictionaryTests {
    // MARK: - Simple Access Tests

    @Test("Access simple string value")
    func testSimpleStringAccess() throws {
        let dict = try NestedDictionary(anyYaml: ["key": "value"])
        let result = try dict.value(at: "key")
        #expect(result == "value")
    }

    @Test("Access simple int value")
    func testSimpleIntAccess() throws {
        let dict = try NestedDictionary(anyYaml: ["port": 8_080])
        let result = try dict.value(at: "port")
        #expect(result == "8080")
    }

    @Test("Access simple bool value")
    func testSimpleBoolAccess() throws {
        let dict = try NestedDictionary(anyYaml: ["enabled": true])
        let result = try dict.value(at: "enabled")
        #expect(result == "true")
    }

    @Test("Access simple double value")
    func testSimpleDoubleAccess() throws {
        let dict = try NestedDictionary(anyYaml: ["version": 1.5])
        let result = try dict.value(at: "version")
        #expect(result == "1.5")
    }

    // MARK: - Nested Access Tests

    @Test("Access nested string value")
    func testNestedAccess() throws {
        let dict = try NestedDictionary(anyYaml: [
            "apps": [
                "ios": [
                    "icon": "AppIcon"
                ]
            ]
        ])
        let result = try dict.value(at: "apps.ios.icon")
        #expect(result == "AppIcon")
    }

    @Test("Access deeply nested value")
    func testDeeplyNestedAccess() throws {
        let dict = try NestedDictionary(anyYaml: [
            "level1": [
                "level2": [
                    "level3": [
                        "level4": "deep value"
                    ]
                ]
            ]
        ])
        let result = try dict.value(at: "level1.level2.level3.level4")
        #expect(result == "deep value")
    }

    @Test("Access nested int value")
    func testNestedIntAccess() throws {
        let dict = try NestedDictionary(anyYaml: [
            "config": [
                "timeout": 30
            ]
        ])
        let result = try dict.value(at: "config.timeout")
        #expect(result == "30")
    }

    @Test("Access nested bool value")
    func testNestedBoolAccess() throws {
        let dict = try NestedDictionary(anyYaml: [
            "features": [
                "debug_menu": false
            ]
        ])
        let result = try dict.value(at: "features.debug_menu")
        #expect(result == "false")
    }

    // MARK: - Missing Key Tests

    @Test("Return nil for missing key")
    func testMissingKey() throws {
        let dict = try NestedDictionary(anyYaml: ["key": "value"])
        let result = try dict.value(at: "missing")
        #expect(result == nil)
    }

    @Test("Return nil for missing nested key")
    func testMissingNestedKey() throws {
        let dict = try NestedDictionary(anyYaml: ["apps": [:]])
        let result = try dict.value(at: "apps.ios.icon")
        #expect(result == nil)
    }

    @Test("Return nil for partially missing path")
    func testPartiallyMissingPath() throws {
        let dict = try NestedDictionary(anyYaml: [
            "apps": [
                "android": [
                    "icon": "AndroidIcon"
                ]
            ]
        ])
        let result = try dict.value(at: "apps.ios.icon")
        #expect(result == nil)
    }

    @Test("Return nil for empty path")
    func testEmptyPath() throws {
        let dict = try NestedDictionary(anyYaml: ["key": "value"])
        let result = try dict.value(at: "")
        #expect(result == nil)
    }

    // MARK: - Non-Terminal Value Tests

    @Test("Return nil for dictionary value (non-terminal)")
    func testDictionaryValue() throws {
        let dict = try NestedDictionary(anyYaml: [
            "apps": [
                "ios": [
                    "icon": "AppIcon"
                ]
            ]
        ])
        // Accessing "apps.ios" should return nil because it's a dictionary
        let result = try dict.value(at: "apps.ios")
        #expect(result == nil)
    }

    @Test("Return nil for root dictionary value")
    func testRootDictionaryValue() throws {
        let dict = try NestedDictionary(anyYaml: [
            "apps": [
                "ios": "value"
            ]
        ])
        // Accessing "apps" should return nil because it's a dictionary
        let result = try dict.value(at: "apps")
        #expect(result == nil)
    }

    // MARK: - Array Access Tests

    @Test("Throw error for array access")
    func testArrayAccessThrowsError() throws {
        let dict = try NestedDictionary(anyYaml: [
            "items": ["one", "two", "three"]
        ])
        #expect(throws: NestedDictionaryError.self) {
            _ = try dict.value(at: "items.0")
        }
    }

    @Test("Throw error for nested array access")
    func testNestedArrayAccessThrowsError() throws {
        let dict = try NestedDictionary(anyYaml: [
            "config": [
                "values": [1, 2, 3]
            ]
        ])
        #expect(throws: NestedDictionaryError.self) {
            _ = try dict.value(at: "config.values.0")
        }
    }

    // MARK: - Type Conversion Tests

    @Test("Convert NSNumber to string")
    func testNSNumberConversion() throws {
        let dict = try NestedDictionary(anyYaml: ["count": NSNumber(value: 42)])
        let result = try dict.value(at: "count")
        #expect(result == "42")
    }

    @Test("Convert Bool NSNumber to string")
    func testBoolNSNumberConversion() throws {
        let dict = try NestedDictionary(anyYaml: ["active": NSNumber(value: true)])
        let result = try dict.value(at: "active")
        #expect(result == "true" || result == "1") // NSNumber bool conversion can vary
    }

    // MARK: - Real-World Scenario Tests

    @Test("Access bundle identifier from nested structure")
    func testBundleIdentifierAccess() throws {
        let dict = try NestedDictionary(anyYaml: [
            "apps": [
                "bundle_identifier": "com.example.app",
                "display_name": "MyApp",
                "ios": [
                    "app_icon_name": "AppIcon",
                    "provision_profile": "Development"
                ]
            ]
        ])

        #expect(try dict.value(at: "apps.bundle_identifier") == "com.example.app")
        #expect(try dict.value(at: "apps.display_name") == "MyApp")
        #expect(try dict.value(at: "apps.ios.app_icon_name") == "AppIcon")
        #expect(try dict.value(at: "apps.ios.provision_profile") == "Development")
    }

    @Test("Access API configuration")
    func testAPIConfigAccess() throws {
        let dict = try NestedDictionary(anyYaml: [
            "api_url": "https://api.example.com",
            "app_url_scheme": "myapp",
            "features": [
                "debug_menu": true,
                "analytics": false
            ]
        ])

        #expect(try dict.value(at: "api_url") == "https://api.example.com")
        #expect(try dict.value(at: "app_url_scheme") == "myapp")
        #expect(try dict.value(at: "features.debug_menu") == "true")
        #expect(try dict.value(at: "features.analytics") == "false")
    }

    // MARK: - Edge Case Tests

    @Test("Handle keys with special characters in name")
    func testSpecialCharacterKeys() throws {
        let dict = try NestedDictionary(anyYaml: [
            "app-name": "MyApp",
            "bundle_id": "com.example"
        ])

        #expect(try dict.value(at: "app-name") == "MyApp")
        #expect(try dict.value(at: "bundle_id") == "com.example")
    }

    @Test("Access value from empty dictionary")
    func testEmptyDictionary() throws {
        let dict = try NestedDictionary(anyYaml: [:])
        let result = try dict.value(at: "any.key")
        #expect(result == nil)
    }

    @Test("Path traversal stops at non-dictionary value")
    func testPathTraversalStopsAtValue() throws {
        let dict = try NestedDictionary(anyYaml: [
            "config": [
                "name": "production"
            ]
        ])
        // Try to traverse past a string value
        let result = try dict.value(at: "config.name.extra")
        #expect(result == nil)
    }
}
