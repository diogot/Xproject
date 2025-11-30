//
// SecretConfig.swift
// Xproject
//
// Configuration models for secret management system
//

import Foundation

// MARK: - Secret Configuration

/// Configuration for secret management system
///
/// Loaded from the `secrets:` section in Xproject.yml, this defines how secrets
/// are encrypted with EJSON and how Swift code is generated with obfuscation.
public struct SecretConfiguration: Codable, Sendable {
    /// Swift code generation configuration for secrets (optional)
    public let swiftGeneration: SecretSwiftGenerationConfig?

    public init(swiftGeneration: SecretSwiftGenerationConfig? = nil) {
        self.swiftGeneration = swiftGeneration
    }

    enum CodingKeys: String, CodingKey {
        case swiftGeneration = "swift_generation"
    }
}

// MARK: - Secret Swift Generation Configuration

/// Configuration for generating Swift code from encrypted secrets
public struct SecretSwiftGenerationConfig: Codable, Sendable {
    /// List of output files to generate
    public let outputs: [SecretSwiftOutput]

    public init(outputs: [SecretSwiftOutput]) {
        self.outputs = outputs
    }
}

// MARK: - Secret Swift Output

/// Configuration for a single generated Swift file
public struct SecretSwiftOutput: Codable, Sendable {
    /// Output file path (relative to working directory)
    public let path: String

    /// Prefixes to filter secrets (e.g., ["all", "ios"])
    /// Secrets are filtered by prefix: "all_api_key", "ios_bundle_id", etc.
    public let prefixes: [String]

    public init(path: String, prefixes: [String]) {
        self.path = path
        self.prefixes = prefixes
    }
}

// MARK: - EJSON File Structure

/// Represents the structure of an EJSON encrypted file (keys.ejson)
///
/// EJSON files contain a public key and encrypted key-value pairs.
/// Format: { "_public_key": "...", "key1": "EJ[1:...]", "key2": "plaintext" }
public struct EJSONFile: Codable, Sendable {
    /// Public key used for encryption (stored in file)
    public let publicKey: String

    /// All key-value pairs (both encrypted and plaintext)
    /// Encrypted values start with "EJ[1:..."
    public let data: [String: String]

    public init(publicKey: String, data: [String: String]) {
        self.publicKey = publicKey
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case publicKey = "_public_key"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.publicKey = try container.decode(String.self, forKey: .publicKey)

        // Decode all other keys as data dictionary
        let allKeys = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var data: [String: String] = [:]
        for key in allKeys.allKeys where key.stringValue != "_public_key" {
            if let value = try? allKeys.decode(String.self, forKey: key) {
                data[key.stringValue] = value
            }
        }
        self.data = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(publicKey, forKey: .publicKey)

        // Encode all data keys
        var allKeys = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in data {
            let codingKey = DynamicCodingKeys(stringValue: key)
            try allKeys.encode(value, forKey: codingKey)
        }
    }

    /// Dynamic coding keys for encoding/decoding arbitrary keys
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }
}

// MARK: - Secret Error

/// Errors that can occur during secret management operations
public enum SecretError: Error, LocalizedError, Sendable {
    case secretsNotEnabled
    case ejsonFileNotFound(path: String)
    case invalidEJSONFormat(path: String, reason: String)
    case privateKeyNotFound(environment: String)
    case encryptionFailed(reason: String)
    case decryptionFailed(reason: String)
    case keychainAccessFailed(reason: String)
    case invalidSecretConfiguration(reason: String)
    case swiftGenerationFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .secretsNotEnabled:
            return """
            Secret management is not configured.

            ✅ Add secrets section to Xproject.yml:
               secrets:
                 swift_generation:
                   outputs:
                     - path: MyApp/Generated/AppKeys.swift
                       prefixes: [all, ios]
            """

        case .ejsonFileNotFound(let path):
            return """
            EJSON file not found at: \(path)

            ✅ Create an EJSON file with:
               xp secrets generate-keys <environment>

            Or manually create: env/<environment>/keys.ejson
            """

        case let .invalidEJSONFormat(path, reason):
            return """
            Invalid EJSON file format at: \(path)

            Reason: \(reason)

            ✅ Make sure the file contains valid JSON with a "_public_key" field.
            """

        case .privateKeyNotFound(let environment):
            return """
            EJSON private key not found for environment: \(environment)

            The private key was not found in:
            1. Environment variable: EJSON_PRIVATE_KEY_\(environment.uppercased())
            2. Environment variable: EJSON_PRIVATE_KEY
            3. macOS Keychain (service: dev.xproject.ejson.<app_name>, account: \(environment))

            ✅ Store the private key in one of these locations:
               export EJSON_PRIVATE_KEY_\(environment.uppercased())="your-64-char-hex-key"
               # or
               security add-generic-password -s dev.xproject.ejson.<app_name> -a \(environment) -w "your-key"
            """

        case .encryptionFailed(let reason):
            return """
            Failed to encrypt secrets.

            Reason: \(reason)

            ✅ Make sure the public key is valid and the JSON is well-formed.
            """

        case .decryptionFailed(let reason):
            return """
            Failed to decrypt secrets.

            Reason: \(reason)

            ✅ Verify the private key matches the public key in the EJSON file.
            """

        case .keychainAccessFailed(let reason):
            return """
            Failed to access macOS Keychain.

            Reason: \(reason)

            ✅ Make sure Xcode/Terminal has Keychain access permission.
            """

        case .invalidSecretConfiguration(let reason):
            return """
            Invalid secret configuration in Xproject.yml.

            Reason: \(reason)

            ✅ Check the secrets section in your configuration file.
            """

        case let .swiftGenerationFailed(path, reason):
            return """
            Failed to generate Swift file at: \(path)

            Reason: \(reason)

            ✅ Make sure the output directory exists and is writable.
            """
        }
    }
}
