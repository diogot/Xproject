//
// KeychainService.swift
// Xproject
//
// Service for storing and retrieving secrets from macOS Keychain
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import Security

/// Service for interacting with macOS Keychain to store EJSON private keys
///
/// This service provides secure storage for EJSON private keys using the macOS Keychain.
/// Keys are stored with service name "dev.xproject.ejson.{appName}" and account name
/// matching the environment name. This ensures each project has unique keychain entries.
///
/// Priority for retrieving keys:
/// 1. Environment variable: `EJSON_PRIVATE_KEY_{ENVIRONMENT}`
/// 2. Environment variable: `EJSON_PRIVATE_KEY`
/// 3. macOS Keychain
/// 4. Interactive prompt (if TTY available and enabled)
/// 5. Error if not found
public final class KeychainService: Sendable {
    /// Service name for EJSON private keys (unique per app)
    private let serviceName: String

    /// Whether interactive prompting is enabled (defaults to true)
    private let interactiveEnabled: Bool

    /// Initializes the KeychainService
    ///
    /// - Parameters:
    ///   - appName: The application name (used in keychain service name)
    ///   - interactiveEnabled: Whether to prompt for keys interactively (default: true)
    public init(appName: String, interactiveEnabled: Bool = true) {
        self.serviceName = "dev.xproject.ejson.\(appName)"
        self.interactiveEnabled = interactiveEnabled
    }

    // MARK: - Public Methods

    /// Retrieves the EJSON private key for a specific environment
    ///
    /// Checks the following locations in order:
    /// 1. Environment variable: `EJSON_PRIVATE_KEY_{ENVIRONMENT}` (uppercased)
    /// 2. Environment variable: `EJSON_PRIVATE_KEY` (global fallback)
    /// 3. macOS Keychain (service: dev.xproject.ejson.{appName}, account: environment)
    /// 4. Interactive prompt (if TTY available and interactiveEnabled is true)
    ///
    /// - Parameter environment: The environment name (e.g., "dev", "staging", "production")
    /// - Returns: The private key as a string
    /// - Throws: `SecretError.privateKeyNotFound` if key is not found in any location
    public func getEJSONPrivateKey(environment: String) throws -> String {
        // Priority 1: Environment variable EJSON_PRIVATE_KEY_{ENVIRONMENT}
        let envVarName = "EJSON_PRIVATE_KEY_\(environment.uppercased())"
        if let key = ProcessInfo.processInfo.environment[envVarName], !key.isEmpty {
            return key
        }

        // Priority 2: Global environment variable EJSON_PRIVATE_KEY
        if let key = ProcessInfo.processInfo.environment["EJSON_PRIVATE_KEY"], !key.isEmpty {
            return key
        }

        // Priority 3: macOS Keychain
        do {
            return try getPassword(service: serviceName, account: environment)
        } catch {
            // Priority 4: Interactive prompt (if enabled and TTY available)
            if interactiveEnabled && Self.isInteractive() {
                return try promptForPrivateKey(environment: environment)
            }
            throw SecretError.privateKeyNotFound(environment: environment)
        }
    }

    // MARK: - Interactive Mode

    /// Checks if the current session is interactive (has a TTY)
    ///
    /// - Returns: True if stdin is a terminal
    public static func isInteractive() -> Bool {
        return isatty(STDIN_FILENO) != 0
    }

    /// Prompts the user interactively for a private key
    ///
    /// Note: This method only prompts and validates the key format. It does NOT offer to save
    /// to the keychain. Use `promptToSavePrivateKey()` after successful decryption to offer saving.
    ///
    /// - Parameter environment: The environment name
    /// - Returns: The private key entered by the user
    /// - Throws: `SecretError.privateKeyNotFound` if no key is entered or key format is invalid
    public func promptForPrivateKey(environment: String) throws -> String {
        print("")
        print("EJSON private key not found for environment: \(environment)")
        print("")
        print("The private key was not found in:")
        print("  1. Environment variable: EJSON_PRIVATE_KEY_\(environment.uppercased())")
        print("  2. Environment variable: EJSON_PRIVATE_KEY")
        print("  3. macOS Keychain (service: \(serviceName), account: \(environment))")
        print("")
        guard let cKey = getpass("Enter EJSON private key (64-character hex string): "),
              let key = String(cString: cKey, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw SecretError.privateKeyNotFound(environment: environment)
        }

        // Validate key format (64 hex characters)
        guard key.count == 64,
              key.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
            print("Invalid key format. Expected 64-character hex string.")
            throw SecretError.privateKeyNotFound(environment: environment)
        }

        return key
    }

    /// Prompts the user to save a private key to the keychain after successful decryption
    ///
    /// This method should be called after verifying the key works (e.g., after successful decryption).
    /// It will only prompt if:
    /// - The session is interactive (TTY available)
    /// - The key is not already stored in the keychain
    ///
    /// - Parameters:
    ///   - key: The private key to potentially save
    ///   - environment: The environment name (used as account name)
    /// - Throws: `SecretError.keychainAccessFailed` if saving to keychain fails
    public func promptToSavePrivateKey(_ key: String, environment: String) throws {
        // Only prompt if interactive
        guard Self.isInteractive() else {
            return
        }

        // Check if already in keychain with same value (skip if already saved)
        if let existingKey = try? getPassword(service: serviceName, account: environment),
           existingKey == key {
            return
        }

        print("Save to keychain for future use? [Y/n]: ", terminator: "")
        let saveResponse = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "y"

        if saveResponse.isEmpty || saveResponse == "y" || saveResponse == "yes" {
            try setEJSONPrivateKey(key, environment: environment)
            print("✓ Private key saved to keychain")
        }
    }

    /// Stores an EJSON private key in the macOS Keychain
    ///
    /// - Parameters:
    ///   - key: The private key to store
    ///   - environment: The environment name (used as account name)
    /// - Throws: `SecretError.keychainAccessFailed` if storage fails
    public func setEJSONPrivateKey(_ key: String, environment: String) throws {
        try setPassword(service: serviceName, account: environment, password: key)
    }

    /// Deletes an EJSON private key from the macOS Keychain
    ///
    /// - Parameter environment: The environment name (used as account name)
    /// - Throws: `SecretError.keychainAccessFailed` if deletion fails
    public func deleteEJSONPrivateKey(environment: String) throws {
        try deletePassword(service: serviceName, account: environment)
    }

    // MARK: - Keychain Operations

    /// Retrieves a password from the macOS Keychain
    ///
    /// - Parameters:
    ///   - service: The service name
    ///   - account: The account name
    /// - Returns: The password as a string
    /// - Throws: `SecretError.keychainAccessFailed` if retrieval fails
    public func getPassword(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            throw SecretError.keychainAccessFailed(reason: "Failed to retrieve password: \(errorMessage)")
        }

        guard let passwordData = item as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw SecretError.keychainAccessFailed(reason: "Failed to decode password data")
        }

        return password
    }

    /// Stores a password in the macOS Keychain
    ///
    /// If an entry already exists, it will be updated.
    ///
    /// - Parameters:
    ///   - service: The service name
    ///   - account: The account name
    ///   - password: The password to store
    /// - Throws: `SecretError.keychainAccessFailed` if storage fails
    public func setPassword(service: String, account: String, password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw SecretError.keychainAccessFailed(reason: "Failed to encode password")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try to update existing item first
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = passwordData

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                let errorMessage = SecCopyErrorMessageString(addStatus, nil) as String? ?? "Unknown error"
                throw SecretError.keychainAccessFailed(reason: "Failed to add password: \(errorMessage)")
            }
        } else if updateStatus != errSecSuccess {
            let errorMessage = SecCopyErrorMessageString(updateStatus, nil) as String? ?? "Unknown error"
            throw SecretError.keychainAccessFailed(reason: "Failed to update password: \(errorMessage)")
        }
    }

    /// Deletes a password from the macOS Keychain
    ///
    /// - Parameters:
    ///   - service: The service name
    ///   - account: The account name
    /// - Throws: `SecretError.keychainAccessFailed` if deletion fails
    public func deletePassword(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            throw SecretError.keychainAccessFailed(reason: "Failed to delete password: \(errorMessage)")
        }
    }
}
