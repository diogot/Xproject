//
// ProvisionConfiguration.swift
// Xproject
//
// Configuration models for provisioning profile management system
//

import Foundation

// MARK: - Provision Configuration

/// Configuration for provisioning profile management system
///
/// Loaded from the `provision:` section in Xproject.yml, this defines how provisioning
/// profiles are encrypted and stored for CI/CD with manual signing workflows.
public struct ProvisionConfiguration: Codable, Sendable {
    /// Whether provision management is enabled
    public let enabled: Bool

    /// Path to the encrypted archive (relative to working directory)
    /// Default: "provision/profiles.zip.enc"
    public let archivePath: String?

    /// Path where decrypted profiles are extracted (relative to working directory)
    /// Default: "provision/profiles/"
    public let extractPath: String?

    /// Path to source profiles directory for encryption (relative to working directory)
    /// Default: "provision/source/"
    public let sourcePath: String?

    /// Profile definitions organized by platform (optional)
    public let profiles: [String: [ProvisionProfile]]?

    public init(
        enabled: Bool,
        archivePath: String? = nil,
        extractPath: String? = nil,
        sourcePath: String? = nil,
        profiles: [String: [ProvisionProfile]]? = nil
    ) {
        self.enabled = enabled
        self.archivePath = archivePath
        self.extractPath = extractPath
        self.sourcePath = sourcePath
        self.profiles = profiles
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case archivePath = "archive_path"
        case extractPath = "extract_path"
        case sourcePath = "source_path"
        case profiles
    }

    // MARK: - Computed Properties with Defaults

    /// Resolved archive path with default
    public var resolvedArchivePath: String {
        archivePath ?? "provision/profiles.zip.enc"
    }

    /// Resolved extract path with default
    public var resolvedExtractPath: String {
        extractPath ?? "provision/profiles/"
    }

    /// Resolved source path with default
    public var resolvedSourcePath: String {
        sourcePath ?? "provision/source/"
    }
}

// MARK: - Provision Profile

/// Metadata for a single provisioning profile
public struct ProvisionProfile: Codable, Sendable {
    /// Human-readable name for the profile
    public let name: String

    /// Filename of the .mobileprovision file
    public let file: String

    public init(name: String, file: String) {
        self.name = name
        self.file = file
    }
}

// MARK: - Provision Error

/// Errors that can occur during provisioning profile management operations
public enum ProvisionError: Error, LocalizedError, Sendable {
    case provisionNotEnabled
    case archiveNotFound(path: String)
    case profileNotFound(path: String)
    case sourceDirectoryNotFound(path: String)
    case noProfilesFound(path: String)
    case encryptionFailed(reason: String)
    case decryptionFailed(reason: String)
    case integrityCheckFailed(reason: String)
    case wrongPassword
    case passwordNotFound
    case installFailed(reason: String)
    case zipFailed(reason: String)
    case unzipFailed(reason: String)
    case cleanupFailed(reason: String)
    case opensslNotFound
    case invalidConfiguration(reason: String)

    public var errorDescription: String? {
        switch self {
        case .provisionNotEnabled:
            return """
            Provisioning profile management is not enabled in configuration.

            ✅ Enable provision in Xproject.yml:
               provision:
                 enabled: true
            """

        case .archiveNotFound(let path):
            return """
            Encrypted provisioning profile archive not found at: \(path)

            ✅ Create an encrypted archive with:
               xp provision encrypt

            Or check that the archive_path in configuration is correct.
            """

        case .profileNotFound(let path):
            return """
            Provisioning profile not found at: \(path)

            ✅ Make sure the profile exists and the path is correct.
            """

        case .sourceDirectoryNotFound(let path):
            return """
            Source directory for provisioning profiles not found at: \(path)

            ✅ Create the source directory and add .mobileprovision files:
               mkdir -p \(path)

            Or specify a different source path with --source option.
            """

        case .noProfilesFound(let path):
            return """
            No .mobileprovision files found in: \(path)

            ✅ Add provisioning profiles to the source directory.
            """

        case .encryptionFailed(let reason):
            return """
            Failed to encrypt provisioning profiles.

            Reason: \(reason)

            ✅ Make sure openssl is available and the password is set:
               export PROVISION_PASSWORD="your-password"
            """

        case .decryptionFailed(let reason):
            return """
            Failed to decrypt provisioning profiles.

            Reason: \(reason)

            ✅ Verify the password is correct and the archive is not corrupted.
            """

        case .integrityCheckFailed(let reason):
            return """
            Integrity check failed for encrypted archive.

            Reason: \(reason)

            ✅ The archive may have been tampered with or corrupted.
               Try re-encrypting from the original profiles.
            """

        case .wrongPassword:
            return """
            Wrong password for encrypted archive.

            ✅ Check your password and try again:
               - Environment variable: PROVISION_PASSWORD
               - Keychain service: dev.xproject.provision.<app_name>
            """

        case .passwordNotFound:
            return """
            Password not found for provisioning profile encryption/decryption.

            The password was not found in:
            1. Environment variable: PROVISION_PASSWORD
            2. macOS Keychain (service: dev.xproject.provision.<app_name>)

            ✅ Set the password in one of these locations:
               export PROVISION_PASSWORD="your-password"
               # or
               security add-generic-password -s dev.xproject.provision.<app_name> \
                   -a provision -w "your-password"
            """

        case .installFailed(let reason):
            return """
            Failed to install provisioning profiles.

            Reason: \(reason)

            ✅ Check that the profiles are decrypted and the target directory is writable:
               ~/Library/MobileDevice/Provisioning Profiles/
            """

        case .zipFailed(let reason):
            return """
            Failed to create ZIP archive.

            Reason: \(reason)

            ✅ Make sure the source files exist and are readable.
            """

        case .unzipFailed(let reason):
            return """
            Failed to extract ZIP archive.

            Reason: \(reason)

            ✅ The archive may be corrupted. Try re-encrypting from original profiles.
            """

        case .cleanupFailed(let reason):
            return """
            Failed to clean up decrypted profiles.

            Reason: \(reason)

            ✅ Check file permissions and try again.
            """

        case .opensslNotFound:
            return """
            OpenSSL not found at /usr/bin/openssl.

            ✅ OpenSSL should be available on all macOS installations.
               If missing, reinstall Xcode Command Line Tools:
               xcode-select --install
            """

        case .invalidConfiguration(let reason):
            return """
            Invalid provision configuration in Xproject.yml.

            Reason: \(reason)

            ✅ Check the provision section in your configuration file.
            """
        }
    }
}
