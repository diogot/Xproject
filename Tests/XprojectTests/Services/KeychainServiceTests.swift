//
// KeychainServiceTests.swift
// XprojectTests
//
// Tests for KeychainService
//

import Foundation
import Testing
@testable import Xproject

@Suite("KeychainService Tests", .serialized)
struct KeychainServiceTests {
    // Use a test-specific service name to avoid conflicts with real data
    private static let testServiceName = "xproject_test_service_\(UUID().uuidString)"
    private static let testAccount = "test_account"
    private static let testAppName = "XprojectTest"

    // MARK: - Basic Keychain Operations

    @Test("Store and retrieve password from keychain")
    func testSetAndGetPassword() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let password = "test_password_123"
        let serviceName = Self.testServiceName + "_1"

        // When
        try service.setPassword(service: serviceName, account: Self.testAccount, password: password)
        let retrieved = try service.getPassword(service: serviceName, account: Self.testAccount)

        // Then
        #expect(retrieved == password)

        // Cleanup
        try? service.deletePassword(service: serviceName, account: Self.testAccount)
    }

    @Test("Update existing password")
    func testUpdatePassword() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let serviceName = Self.testServiceName + "_2"
        let originalPassword = "original_password"
        let updatedPassword = "updated_password"

        // When
        try service.setPassword(service: serviceName, account: Self.testAccount, password: originalPassword)
        try service.setPassword(service: serviceName, account: Self.testAccount, password: updatedPassword)
        let retrieved = try service.getPassword(service: serviceName, account: Self.testAccount)

        // Then
        #expect(retrieved == updatedPassword)

        // Cleanup
        try? service.deletePassword(service: serviceName, account: Self.testAccount)
    }

    @Test("Delete password from keychain")
    func testDeletePassword() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let serviceName = Self.testServiceName + "_3"
        let password = "password_to_delete"

        // When
        try service.setPassword(service: serviceName, account: Self.testAccount, password: password)
        try service.deletePassword(service: serviceName, account: Self.testAccount)

        // Then - trying to get should fail
        do {
            _ = try service.getPassword(service: serviceName, account: Self.testAccount)
            #expect(Bool(false), "Expected error when getting deleted password")
        } catch let error as SecretError {
            guard case .keychainAccessFailed = error else {
                #expect(Bool(false), "Expected keychainAccessFailed error")
                return
            }
        }
    }

    @Test("Delete non-existent password succeeds")
    func testDeleteNonExistentPassword() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let serviceName = Self.testServiceName + "_4"

        // When/Then - should not throw
        try service.deletePassword(service: serviceName, account: "non_existent_account")
    }

    @Test("Get non-existent password throws error")
    func testGetNonExistentPassword() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let serviceName = Self.testServiceName + "_5"

        // When/Then
        do {
            _ = try service.getPassword(service: serviceName, account: "non_existent_account")
            #expect(Bool(false), "Expected error when getting non-existent password")
        } catch let error as SecretError {
            guard case .keychainAccessFailed = error else {
                #expect(Bool(false), "Expected keychainAccessFailed error")
                return
            }
        }
    }

    // MARK: - EJSON Private Key Operations

    @Test("Store and retrieve EJSON private key")
    func testSetAndGetEJSONPrivateKey() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let environment = "test_env_1"
        let privateKey = "a1b2c3d4e5f6" + String(repeating: "0", count: 52) // 64 chars

        // When
        try service.setEJSONPrivateKey(privateKey, environment: environment)
        let retrieved = try service.getEJSONPrivateKey(environment: environment)

        // Then
        #expect(retrieved == privateKey)

        // Cleanup
        try? service.deleteEJSONPrivateKey(environment: environment)
    }

    @Test("Get EJSON private key from environment variable with environment suffix")
    func testGetEJSONPrivateKeyFromEnvVarWithSuffix() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let environment = "dev"
        let privateKey = "env_var_key_" + String(repeating: "x", count: 52)

        // Set environment variable
        setenv("EJSON_PRIVATE_KEY_DEV", privateKey, 1)

        // When
        let retrieved = try service.getEJSONPrivateKey(environment: environment)

        // Then
        #expect(retrieved == privateKey)

        // Cleanup
        unsetenv("EJSON_PRIVATE_KEY_DEV")
    }

    @Test("Get EJSON private key from global environment variable")
    func testGetEJSONPrivateKeyFromGlobalEnvVar() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let environment = "staging_global_test"
        let privateKey = "global_key_" + String(repeating: "y", count: 54)

        // Cleanup any existing env vars first (tests run in parallel)
        let envVarName = "EJSON_PRIVATE_KEY_\(environment.uppercased())"
        unsetenv(envVarName.cString(using: .utf8))

        // Set global environment variable
        setenv("EJSON_PRIVATE_KEY", privateKey, 1)

        // When
        let retrieved = try service.getEJSONPrivateKey(environment: environment)

        // Then
        #expect(retrieved == privateKey)

        // Cleanup
        unsetenv("EJSON_PRIVATE_KEY")
    }

    @Test("Environment variable with environment suffix takes priority over global")
    func testEnvVarPriority() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let environment = "production"
        let specificKey = "specific_key_" + String(repeating: "a", count: 51)
        let globalKey = "global_key_" + String(repeating: "b", count: 54)

        // Set both environment variables
        setenv("EJSON_PRIVATE_KEY_PRODUCTION", specificKey, 1)
        setenv("EJSON_PRIVATE_KEY", globalKey, 1)

        // When
        let retrieved = try service.getEJSONPrivateKey(environment: environment)

        // Then - should get the specific one, not the global
        #expect(retrieved == specificKey)

        // Cleanup
        unsetenv("EJSON_PRIVATE_KEY_PRODUCTION")
        unsetenv("EJSON_PRIVATE_KEY")
    }

    @Test("Global environment variable takes priority over keychain")
    func testGlobalEnvVarOverKeychain() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let environment = "test_env_2"
        let keychainKey = "keychain_key_" + String(repeating: "k", count: 51)
        let envVarKey = "env_var_key_" + String(repeating: "e", count: 51)

        // Store in keychain
        try service.setEJSONPrivateKey(keychainKey, environment: environment)

        // Set global environment variable
        setenv("EJSON_PRIVATE_KEY", envVarKey, 1)

        // When
        let retrieved = try service.getEJSONPrivateKey(environment: environment)

        // Then - should get env var, not keychain
        #expect(retrieved == envVarKey)

        // Cleanup
        unsetenv("EJSON_PRIVATE_KEY")
        try? service.deleteEJSONPrivateKey(environment: environment)
    }

    @Test("Get EJSON private key throws when not found")
    func testGetEJSONPrivateKeyNotFound() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let environment = "non_existent_env_unique"

        // Clear all environment variables that could interfere (tests run in parallel)
        let specificEnvVar = "EJSON_PRIVATE_KEY_\(environment.uppercased())"
        unsetenv(specificEnvVar.cString(using: .utf8))
        unsetenv("EJSON_PRIVATE_KEY")

        // When/Then
        do {
            _ = try service.getEJSONPrivateKey(environment: environment)
            #expect(Bool(false), "Expected privateKeyNotFound error")
        } catch let error as SecretError {
            guard case .privateKeyNotFound(let env) = error else {
                #expect(Bool(false), "Expected privateKeyNotFound error")
                return
            }
            #expect(env == environment)
        }
    }

    // MARK: - Special Characters

    @Test("Store password with special characters")
    func testPasswordWithSpecialCharacters() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let serviceName = Self.testServiceName + "_6"
        let password = "!@#$%^&*()_+-={}[]|\\:;\"'<>,.?/~`"

        // When
        try service.setPassword(service: serviceName, account: Self.testAccount, password: password)
        let retrieved = try service.getPassword(service: serviceName, account: Self.testAccount)

        // Then
        #expect(retrieved == password)

        // Cleanup
        try? service.deletePassword(service: serviceName, account: Self.testAccount)
    }

    @Test("Store password with Unicode characters")
    func testPasswordWithUnicode() throws {
        // Given
        let service = KeychainService(appName: Self.testAppName)
        let serviceName = Self.testServiceName + "_7"
        let password = "Hello世界🌍Ñoño"

        // When
        try service.setPassword(service: serviceName, account: Self.testAccount, password: password)
        let retrieved = try service.getPassword(service: serviceName, account: Self.testAccount)

        // Then
        #expect(retrieved == password)

        // Cleanup
        try? service.deletePassword(service: serviceName, account: Self.testAccount)
    }

    // MARK: - Interactive Mode

    @Test("isInteractive returns a boolean")
    func testIsInteractiveReturnsBool() {
        // When
        let result = KeychainService.isInteractive()

        // Then - Just verify it returns a boolean (actual value depends on test environment)
        #expect(result == true || result == false)
    }

    @Test("Non-interactive service throws privateKeyNotFound without prompting")
    func testNonInteractiveThrowsWithoutPrompt() throws {
        // Given - create service with interactive disabled
        let service = KeychainService(appName: Self.testAppName, interactiveEnabled: false)
        let environment = "non_interactive_test_env"

        // Clear environment variables
        let specificEnvVar = "EJSON_PRIVATE_KEY_\(environment.uppercased())"
        unsetenv(specificEnvVar.cString(using: .utf8))
        unsetenv("EJSON_PRIVATE_KEY")

        // Make sure no keychain entry exists
        try? service.deleteEJSONPrivateKey(environment: environment)

        // When/Then - should throw privateKeyNotFound without attempting to prompt
        do {
            _ = try service.getEJSONPrivateKey(environment: environment)
            #expect(Bool(false), "Expected privateKeyNotFound error")
        } catch let error as SecretError {
            guard case .privateKeyNotFound(let env) = error else {
                #expect(Bool(false), "Expected privateKeyNotFound error, got \(error)")
                return
            }
            #expect(env == environment)
        }
    }
}
