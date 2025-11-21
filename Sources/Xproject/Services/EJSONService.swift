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
