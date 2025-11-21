//
// EJSONService.swift
// Xproject
//
// Service for EJSON file encryption and decryption using the swift-ejson library
//

import EJSONKit
import Foundation

/// Service for managing EJSON encrypted files
///
/// This service provides a wrapper around the swift-ejson library with support for
/// working directory resolution and error handling. EJSON files use asymmetric
/// encryption (NaCl Box) to protect secrets at rest.
///
/// Format: `EJ[1:ephemeral_pk:nonce:ciphertext]`
public final class EJSONService {
    private let workingDirectory: String
    private let fileManager: FileManager
    private let ejson: EJSON

    /// Initialize the EJSON service
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory for resolving relative paths
    ///   - fileManager: The file manager to use (defaults to .default)
    public init(workingDirectory: String, fileManager: FileManager = .default) {
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.ejson = EJSON()
    }

    // MARK: - Key Generation

    /// Generates a new EJSON key pair
    ///
    /// - Returns: Tuple containing public and private keys (64-character hex strings)
    /// - Throws: `SecretError.encryptionFailed` if key generation fails
    public func generateKeyPair() throws -> (publicKey: String, privateKey: String) {
        do {
            let keyPair = try ejson.generateKeyPair()
            return (publicKey: keyPair.publicKey, privateKey: keyPair.privateKey)
        } catch {
            throw SecretError.encryptionFailed(reason: "Failed to generate EJSON key pair: \(error.localizedDescription)")
        }
    }

    // MARK: - File Operations

    /// Encrypts an EJSON file in place
    ///
    /// The file must already exist and contain a `_public_key` field. All string values
    /// that don't start with "EJ[1:" will be encrypted.
    ///
    /// - Parameter path: Path to the EJSON file (relative to working directory)
    /// - Throws: `SecretError.ejsonFileNotFound` if file doesn't exist
    /// - Throws: `SecretError.encryptionFailed` if encryption fails
    public func encryptFile(path: String) throws {
        let fullPath = resolvePath(path)

        // Check if file exists
        guard fileManager.fileExists(atPath: fullPath) else {
            throw SecretError.ejsonFileNotFound(path: fullPath)
        }

        // Extract public key from file
        let publicKey = try extractPublicKey(path: path)

        // Encrypt the file
        do {
            try ejson.encryptFile(at: fullPath, publicKey: publicKey)
        } catch {
            throw SecretError.encryptionFailed(reason: error.localizedDescription)
        }
    }

    /// Decrypts an EJSON file and returns the decrypted data
    ///
    /// - Parameters:
    ///   - path: Path to the EJSON file (relative to working directory)
    ///   - privateKey: The private key for decryption (64-character hex string)
    /// - Returns: Dictionary containing the decrypted key-value pairs
    /// - Throws: `SecretError.ejsonFileNotFound` if file doesn't exist
    /// - Throws: `SecretError.decryptionFailed` if decryption fails
    public func decryptFile(path: String, privateKey: String) throws -> [String: Any] {
        let fullPath = resolvePath(path)

        // Check if file exists
        guard fileManager.fileExists(atPath: fullPath) else {
            throw SecretError.ejsonFileNotFound(path: fullPath)
        }

        // Decrypt the file
        do {
            return try ejson.decryptFile(at: fullPath, privateKey: privateKey)
        } catch {
            throw SecretError.decryptionFailed(reason: error.localizedDescription)
        }
    }

    /// Extracts the public key from an EJSON file
    ///
    /// - Parameter path: Path to the EJSON file (relative to working directory)
    /// - Returns: The public key (64-character hex string)
    /// - Throws: `SecretError.ejsonFileNotFound` if file doesn't exist
    /// - Throws: `SecretError.invalidEJSONFormat` if file doesn't contain a valid public key
    public func extractPublicKey(path: String) throws -> String {
        let fullPath = resolvePath(path)

        // Check if file exists
        guard fileManager.fileExists(atPath: fullPath) else {
            throw SecretError.ejsonFileNotFound(path: fullPath)
        }

        // Extract public key
        do {
            return try ejson.extractPublicKey(from: fullPath)
        } catch {
            throw SecretError.invalidEJSONFormat(
                path: fullPath,
                reason: "Failed to extract public key: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Value Operations

    /// Encrypts a single string value
    ///
    /// - Parameters:
    ///   - value: The plaintext string to encrypt
    ///   - publicKey: The public key for encryption (64-character hex string)
    /// - Returns: Encrypted value in format `EJ[1:ephemeral_pk:nonce:ciphertext]`
    /// - Throws: `SecretError.encryptionFailed` if encryption fails
    public func encrypt(_ value: String, publicKey: String) throws -> String {
        do {
            return try ejson.encrypt(value, publicKey: publicKey)
        } catch {
            throw SecretError.encryptionFailed(reason: error.localizedDescription)
        }
    }

    /// Decrypts a single encrypted value
    ///
    /// - Parameters:
    ///   - ciphertext: The encrypted value (format: `EJ[1:...]`)
    ///   - privateKey: The private key for decryption (64-character hex string)
    /// - Returns: The decrypted plaintext string
    /// - Throws: `SecretError.decryptionFailed` if decryption fails
    public func decrypt(_ ciphertext: String, privateKey: String) throws -> String {
        do {
            return try ejson.decrypt(ciphertext, privateKey: privateKey)
        } catch {
            throw SecretError.decryptionFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Validation

    /// Result of validating an EJSON file
    public struct ValidationResult: Sendable {
        /// Whether the file is valid
        public let isValid: Bool
        /// List of validation issues (warnings or errors)
        public let issues: [ValidationIssue]
        /// The public key if found
        public let publicKey: String?
        /// Total number of secrets (excluding _public_key)
        public let secretCount: Int
        /// Number of encrypted secrets
        public let encryptedCount: Int
        /// Number of plaintext secrets
        public let plaintextCount: Int

        public init(
            isValid: Bool,
            issues: [ValidationIssue],
            publicKey: String?,
            secretCount: Int,
            encryptedCount: Int,
            plaintextCount: Int
        ) {
            self.isValid = isValid
            self.issues = issues
            self.publicKey = publicKey
            self.secretCount = secretCount
            self.encryptedCount = encryptedCount
            self.plaintextCount = plaintextCount
        }
    }

    /// A validation issue found during EJSON validation
    public struct ValidationIssue: Sendable {
        public enum Severity: Sendable {
            case warning
            case error
        }

        public let severity: Severity
        public let message: String

        public init(severity: Severity, message: String) {
            self.severity = severity
            self.message = message
        }
    }

    /// Validates an EJSON file without decrypting it
    ///
    /// Checks:
    /// - File exists and is valid JSON
    /// - Public key is present and has valid format (64-char hex)
    /// - Reports encryption status of each secret
    ///
    /// - Parameter path: Path to the EJSON file (relative to working directory)
    /// - Returns: ValidationResult with details about the file
    public func validateFile(path: String) -> ValidationResult {
        let fullPath = resolvePath(path)
        var issues: [ValidationIssue] = []
        var publicKey: String?
        var secretCount = 0
        var encryptedCount = 0
        var plaintextCount = 0

        // Check file exists
        guard fileManager.fileExists(atPath: fullPath) else {
            return ValidationResult(
                isValid: false,
                issues: [ValidationIssue(severity: .error, message: "File not found: \(path)")],
                publicKey: nil,
                secretCount: 0,
                encryptedCount: 0,
                plaintextCount: 0
            )
        }

        // Read and parse JSON
        guard let data = fileManager.contents(atPath: fullPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ValidationResult(
                isValid: false,
                issues: [ValidationIssue(severity: .error, message: "File is not valid JSON")],
                publicKey: nil,
                secretCount: 0,
                encryptedCount: 0,
                plaintextCount: 0
            )
        }

        // Check public key
        if let pk = json["_public_key"] as? String {
            publicKey = pk
            if !isValidPublicKey(pk) {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Invalid public key format (expected 64-character hex string)"
                ))
            }
        } else {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Missing _public_key field"
            ))
        }

        // Check secrets
        for (key, value) in json where key != "_public_key" {
            secretCount += 1
            if let stringValue = value as? String {
                if stringValue.hasPrefix("EJ[1:") {
                    encryptedCount += 1
                } else {
                    plaintextCount += 1
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Secret '\(key)' is not encrypted"
                    ))
                }
            } else {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Secret '\(key)' is not a string value"
                ))
            }
        }

        let hasErrors = issues.contains { $0.severity == .error }
        return ValidationResult(
            isValid: !hasErrors,
            issues: issues,
            publicKey: publicKey,
            secretCount: secretCount,
            encryptedCount: encryptedCount,
            plaintextCount: plaintextCount
        )
    }

    /// Validates all EJSON files in all environment directories
    ///
    /// - Returns: Dictionary mapping environment names to their validation results
    public func validateAllEnvironments() -> [String: ValidationResult] {
        let envDir = resolvePath("env")
        var results: [String: ValidationResult] = [:]

        guard fileManager.fileExists(atPath: envDir),
              let contents = try? fileManager.contentsOfDirectory(atPath: envDir) else {
            return results
        }

        for item in contents {
            let keysPath = "env/\(item)/keys.ejson"
            let fullKeysPath = resolvePath(keysPath)

            if fileManager.fileExists(atPath: fullKeysPath) {
                results[item] = validateFile(path: keysPath)
            }
        }

        return results
    }

    /// Checks if a public key has valid format (64-character hex string)
    ///
    /// - Parameter key: The public key to validate
    /// - Returns: True if the key is valid
    public func isValidPublicKey(_ key: String) -> Bool {
        guard key.count == 64 else { return false }
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return key.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }

    // MARK: - Batch Operations

    /// Encrypts all EJSON files in all environment directories
    ///
    /// Searches for `env/*/keys.ejson` files and encrypts them in place.
    ///
    /// - Returns: List of file paths that were encrypted
    /// - Throws: Various `SecretError` cases if encryption fails
    public func encryptAllEnvironments() throws -> [String] {
        let envDir = resolvePath("env")
        var encryptedFiles: [String] = []

        // Check if env directory exists
        guard fileManager.fileExists(atPath: envDir) else {
            return []
        }

        // Get all subdirectories in env/
        guard let contents = try? fileManager.contentsOfDirectory(atPath: envDir) else {
            return []
        }

        // Encrypt keys.ejson in each environment
        for item in contents {
            let keysPath = "env/\(item)/keys.ejson"
            let fullKeysPath = resolvePath(keysPath)

            if fileManager.fileExists(atPath: fullKeysPath) {
                try encryptFile(path: keysPath)
                encryptedFiles.append(keysPath)
            }
        }

        return encryptedFiles
    }

    // MARK: - Private Helpers

    /// Resolves a relative path to an absolute path based on working directory
    ///
    /// - Parameter path: The relative or absolute path
    /// - Returns: The absolute path
    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDirectory as NSString).appendingPathComponent(path)
    }
}
