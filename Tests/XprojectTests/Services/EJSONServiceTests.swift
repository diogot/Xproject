//
// EJSONServiceTests.swift
// XprojectTests
//
// Tests for EJSONService
//

import Foundation
import Testing
@testable import Xproject

@Suite("EJSONService Tests", .serialized)
struct EJSONServiceTests {
    // MARK: - Key Generation

    @Test("Generate EJSON key pair")
    func testGenerateKeyPair() throws {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")

        // When
        let (publicKey, privateKey) = try service.generateKeyPair()

        // Then
        #expect(publicKey.count == 64) // 32 bytes = 64 hex chars
        #expect(privateKey.count == 64)
        #expect(publicKey != privateKey)

        // Verify they're valid hex strings
        #expect(publicKey.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
        #expect(privateKey.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
    }

    @Test("Multiple key pair generations produce different keys")
    func testMultipleKeyPairGenerations() throws {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")

        // When
        let (pub1, priv1) = try service.generateKeyPair()
        let (pub2, priv2) = try service.generateKeyPair()

        // Then - each generation should produce unique keys
        #expect(pub1 != pub2)
        #expect(priv1 != priv2)
    }

    // MARK: - Value Encryption/Decryption

    @Test("Encrypt and decrypt single value")
    func testEncryptDecryptValue() throws {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")
        let (publicKey, privateKey) = try service.generateKeyPair()
        let originalValue = "my_secret_api_key_12345"

        // When
        let encrypted = try service.encrypt(originalValue, publicKey: publicKey)
        let decrypted = try service.decrypt(encrypted, privateKey: privateKey)

        // Then
        #expect(encrypted.hasPrefix("EJ[1:")) // EJSON format
        #expect(encrypted != originalValue) // Should be encrypted
        #expect(decrypted == originalValue) // Should decrypt correctly
    }

    @Test("Encrypted values are different each time")
    func testEncryptionRandomness() throws {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")
        let (publicKey, _) = try service.generateKeyPair()
        let value = "test_value"

        // When
        let encrypted1 = try service.encrypt(value, publicKey: publicKey)
        let encrypted2 = try service.encrypt(value, publicKey: publicKey)

        // Then - should produce different ciphertexts due to random nonce
        #expect(encrypted1 != encrypted2)
    }

    // MARK: - File Operations

    @Test("Create, encrypt, and decrypt EJSON file")
    func testFileEncryptDecrypt() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)
        let (publicKey, privateKey) = try service.generateKeyPair()

        // Create a test EJSON file
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let initialJSON = """
        {
          "_public_key": "\(publicKey)",
          "api_key": "secret_value_123",
          "database_password": "super_secret_password"
        }
        """
        try initialJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When - encrypt the file
        try service.encryptFile(path: "keys.ejson")

        // Verify file was encrypted
        let encryptedContent = try String(contentsOf: testFile, encoding: .utf8)
        #expect(encryptedContent.contains("EJ[1:")) // Should contain encrypted values
        #expect(!encryptedContent.contains("secret_value_123")) // Should not contain plaintext

        // When - decrypt the file
        let decrypted = try service.decryptFile(path: "keys.ejson", privateKey: privateKey)

        // Then
        #expect(decrypted["api_key"] as? String == "secret_value_123")
        #expect(decrypted["database_password"] as? String == "super_secret_password")
    }

    @Test("Extract public key from EJSON file")
    func testExtractPublicKey() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)
        let (publicKey, _) = try service.generateKeyPair()

        // Create a test EJSON file
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let testJSON = """
        {
          "_public_key": "\(publicKey)",
          "some_key": "some_value"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When
        let extractedKey = try service.extractPublicKey(path: "keys.ejson")

        // Then
        #expect(extractedKey == publicKey)
    }

    // MARK: - Error Handling

    @Test("Encrypt non-existent file throws error")
    func testEncryptNonExistentFile() throws {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")

        // When/Then
        do {
            try service.encryptFile(path: "non_existent_file.ejson")
            #expect(Bool(false), "Expected ejsonFileNotFound error")
        } catch let error as SecretError {
            guard case .ejsonFileNotFound = error else {
                #expect(Bool(false), "Expected ejsonFileNotFound error")
                return
            }
        }
    }

    @Test("Decrypt non-existent file throws error")
    func testDecryptNonExistentFile() throws {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")

        // When/Then
        do {
            _ = try service.decryptFile(path: "non_existent_file.ejson", privateKey: String(repeating: "0", count: 64))
            #expect(Bool(false), "Expected ejsonFileNotFound error")
        } catch let error as SecretError {
            guard case .ejsonFileNotFound = error else {
                #expect(Bool(false), "Expected ejsonFileNotFound error")
                return
            }
        }
    }

    @Test("Decrypt with wrong private key throws error")
    func testDecryptWithWrongKey() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)
        let (publicKey, privateKey) = try service.generateKeyPair()
        let (_, wrongPrivateKey) = try service.generateKeyPair() // Different key pair

        // Create a test file with properly encrypted value
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let encryptedValue = try service.encrypt("secret_value", publicKey: publicKey)
        let testJSON = """
        {
          "_public_key": "\(publicKey)",
          "api_key": "\(encryptedValue)"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // Verify it works with the correct key first
        let decryptedCorrect = try service.decryptFile(path: "keys.ejson", privateKey: privateKey)
        #expect(decryptedCorrect["api_key"] as? String == "secret_value")

        // When/Then - try with wrong key
        do {
            _ = try service.decryptFile(path: "keys.ejson", privateKey: wrongPrivateKey)
            #expect(Bool(false), "Expected decryptionFailed error")
        } catch let error as SecretError {
            guard case .decryptionFailed = error else {
                #expect(Bool(false), "Expected decryptionFailed error")
                return
            }
        }
    }

    // MARK: - Path Resolution

    @Test("Resolve relative paths correctly")
    func testPathResolution() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)
        let (publicKey, _) = try service.generateKeyPair()

        // Create a test file in subdirectory
        let subDir = tempDir.appendingPathComponent("env/dev")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let testFile = subDir.appendingPathComponent("keys.ejson")
        let testJSON = """
        {
          "_public_key": "\(publicKey)",
          "key": "value"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When - extract using relative path
        let extractedKey = try service.extractPublicKey(path: "env/dev/keys.ejson")

        // Then
        #expect(extractedKey == publicKey)
    }

    // MARK: - Batch Operations

    @Test("Encrypt all environments")
    func testEncryptAllEnvironments() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // Create multiple environment directories with keys.ejson files
        let environments = ["dev", "staging", "production"]
        var keyPairs: [(String, String)] = []

        for env in environments {
            let envDir = tempDir.appendingPathComponent("env/\(env)")
            try FileManager.default.createDirectory(at: envDir, withIntermediateDirectories: true)

            let (publicKey, privateKey) = try service.generateKeyPair()
            keyPairs.append((publicKey, privateKey))

            let testFile = envDir.appendingPathComponent("keys.ejson")
            let testJSON = """
            {
              "_public_key": "\(publicKey)",
              "\(env)_api_key": "secret_\(env)_value"
            }
            """
            try testJSON.write(to: testFile, atomically: true, encoding: .utf8)
        }

        // When
        let encryptedFiles = try service.encryptAllEnvironments()

        // Then
        #expect(encryptedFiles.count == 3)
        #expect(encryptedFiles.contains("env/dev/keys.ejson"))
        #expect(encryptedFiles.contains("env/staging/keys.ejson"))
        #expect(encryptedFiles.contains("env/production/keys.ejson"))

        // Verify all files were actually encrypted
        for (index, env) in environments.enumerated() {
            let filePath = tempDir.appendingPathComponent("env/\(env)/keys.ejson")
            let content = try String(contentsOf: filePath, encoding: .utf8)
            #expect(content.contains("EJ[1:"))
            #expect(!content.contains("secret_\(env)_value"))

            // Verify they can be decrypted with the correct key
            let decrypted = try service.decryptFile(
                path: "env/\(env)/keys.ejson",
                privateKey: keyPairs[index].1
            )
            #expect(decrypted["\(env)_api_key"] as? String == "secret_\(env)_value")
        }
    }

    @Test("Encrypt all environments with no env directory")
    func testEncryptAllEnvironmentsNoEnvDir() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // When - no env directory exists
        let encryptedFiles = try service.encryptAllEnvironments()

        // Then - should return empty array, not error
        #expect(encryptedFiles.isEmpty)
    }

    @Test("Encrypt all environments with empty env directory")
    func testEncryptAllEnvironmentsEmptyEnvDir() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        let envDir = tempDir.appendingPathComponent("env")
        try FileManager.default.createDirectory(at: envDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // When
        let encryptedFiles = try service.encryptAllEnvironments()

        // Then
        #expect(encryptedFiles.isEmpty)
    }

    // MARK: - Validation

    @Test("Validate valid EJSON file with all encrypted secrets")
    func testValidateValidEncryptedFile() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)
        let (publicKey, _) = try service.generateKeyPair()

        // Create a valid EJSON file with encrypted values
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let encryptedValue = try service.encrypt("secret", publicKey: publicKey)
        let testJSON = """
        {
          "_public_key": "\(publicKey)",
          "api_key": "\(encryptedValue)"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When
        let result = service.validateFile(path: "keys.ejson")

        // Then
        #expect(result.isValid)
        #expect(result.publicKey == publicKey)
        #expect(result.secretCount == 1)
        #expect(result.encryptedCount == 1)
        #expect(result.plaintextCount == 0)
        #expect(result.issues.isEmpty)
    }

    @Test("Validate EJSON file with plaintext secrets (warnings)")
    func testValidateFileWithPlaintextSecrets() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)
        let (publicKey, _) = try service.generateKeyPair()

        // Create a file with plaintext secrets
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let testJSON = """
        {
          "_public_key": "\(publicKey)",
          "api_key": "plaintext_secret"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When
        let result = service.validateFile(path: "keys.ejson")

        // Then - still valid but with warnings
        #expect(result.isValid)
        #expect(result.secretCount == 1)
        #expect(result.encryptedCount == 0)
        #expect(result.plaintextCount == 1)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].severity == .warning)
        #expect(result.issues[0].message.contains("api_key"))
    }

    @Test("Validate non-existent file returns error")
    func testValidateNonExistentFile() {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")

        // When
        let result = service.validateFile(path: "non_existent.ejson")

        // Then
        #expect(!result.isValid)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].severity == .error)
        #expect(result.issues[0].message.contains("not found"))
    }

    @Test("Validate invalid JSON file returns error")
    func testValidateInvalidJSONFile() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // Create an invalid JSON file
        let testFile = tempDir.appendingPathComponent("invalid.ejson")
        try "not valid json {".write(to: testFile, atomically: true, encoding: .utf8)

        // When
        let result = service.validateFile(path: "invalid.ejson")

        // Then
        #expect(!result.isValid)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].severity == .error)
        #expect(result.issues[0].message.contains("not valid JSON"))
    }

    @Test("Validate file missing public key returns error")
    func testValidateMissingPublicKey() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // Create a file without _public_key
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let testJSON = """
        {
          "api_key": "some_value"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When
        let result = service.validateFile(path: "keys.ejson")

        // Then
        #expect(!result.isValid)
        #expect(result.publicKey == nil)
        let errors = result.issues.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("Missing _public_key") })
    }

    @Test("Validate file with invalid public key format returns error")
    func testValidateInvalidPublicKeyFormat() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // Create a file with invalid public key (too short)
        let testFile = tempDir.appendingPathComponent("keys.ejson")
        let testJSON = """
        {
          "_public_key": "abc123",
          "api_key": "value"
        }
        """
        try testJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // When
        let result = service.validateFile(path: "keys.ejson")

        // Then
        #expect(!result.isValid)
        let errors = result.issues.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("Invalid public key format") })
    }

    @Test("isValidPublicKey validates correctly")
    func testIsValidPublicKey() {
        // Given
        let service = EJSONService(workingDirectory: "/tmp")

        // Valid key (64 hex chars)
        let validKey = String(repeating: "0", count: 64)
        #expect(service.isValidPublicKey(validKey))

        let validKeyMixed = "0123456789abcdefABCDEF0123456789abcdefABCDEF0123456789abcdefABCD"
        #expect(service.isValidPublicKey(validKeyMixed))

        // Invalid keys
        #expect(!service.isValidPublicKey("abc123")) // Too short
        #expect(!service.isValidPublicKey(String(repeating: "0", count: 63))) // 63 chars
        #expect(!service.isValidPublicKey(String(repeating: "0", count: 65))) // 65 chars
        #expect(!service.isValidPublicKey(String(repeating: "g", count: 64))) // Invalid hex
    }

    @Test("Validate all environments")
    func testValidateAllEnvironments() throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ejson_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = EJSONService(workingDirectory: tempDir.path)

        // Create multiple environments
        let environments = ["dev", "staging"]
        for env in environments {
            let envDir = tempDir.appendingPathComponent("env/\(env)")
            try FileManager.default.createDirectory(at: envDir, withIntermediateDirectories: true)

            let (publicKey, _) = try service.generateKeyPair()
            let testFile = envDir.appendingPathComponent("keys.ejson")
            let testJSON = """
            {
              "_public_key": "\(publicKey)",
              "\(env)_key": "value"
            }
            """
            try testJSON.write(to: testFile, atomically: true, encoding: .utf8)
        }

        // When
        let results = service.validateAllEnvironments()

        // Then
        #expect(results.count == 2)
        #expect(results["dev"] != nil)
        #expect(results["staging"] != nil)
        #expect(results["dev"]!.isValid)
        #expect(results["staging"]!.isValid)
    }
}
