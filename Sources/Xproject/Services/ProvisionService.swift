//
// ProvisionService.swift
// Xproject
//
// Service for managing encrypted provisioning profile archives
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Security

/// Service for managing encrypted provisioning profile archives
///
/// This service handles encryption/decryption of provisioning profiles using AES-256-CBC
/// via the system's `/usr/bin/openssl` command. Profiles are stored in a ZIP archive that
/// is encrypted for secure storage in repositories.
///
/// Security features:
/// - AES-256-CBC encryption with PBKDF2 key derivation
/// - PBKDF2 key derivation with 100,000 iterations
/// - Password passed via environment variable (not command line)
public final class ProvisionService { // swiftlint:disable:this type_body_length
    private let workingDirectory: String
    private let fileManager: FileManager
    private let executor: CommandExecutor
    private let appName: String
    private let interactiveEnabled: Bool

    /// Keychain service name for provision password
    private var keychainServiceName: String {
        "dev.xproject.provision.\(appName)"
    }

    /// Path to the staging directory for temporary files
    private var stagingDirectory: String {
        resolvePath("tmp/provision")
    }

    /// System provisioning profiles directory
    private let systemProfilesPath = NSString(
        string: "~/Library/MobileDevice/Provisioning Profiles"
    ).expandingTildeInPath

    // MARK: - Initialization

    /// Initialize the provision service
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory for resolving relative paths
    ///   - appName: The application name (used for keychain service name)
    ///   - fileManager: The file manager to use
    ///   - dryRun: Whether to run in dry-run mode
    ///   - verbose: Whether to show verbose output
    ///   - interactiveEnabled: Whether interactive prompts are enabled
    public init(
        workingDirectory: String,
        appName: String,
        fileManager: FileManager,
        dryRun: Bool,
        verbose: Bool,
        interactiveEnabled: Bool
    ) {
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.executor = CommandExecutor(workingDirectory: workingDirectory, dryRun: dryRun, verbose: verbose)
        self.appName = appName
        self.interactiveEnabled = interactiveEnabled
    }

    // MARK: - Encrypt Profiles

    /// Result of encrypting profiles
    public struct EncryptResult: Sendable {
        /// Number of profiles archived
        public let profileCount: Int
        /// Path to the encrypted archive
        public let archivePath: String
        /// Size of the encrypted archive in bytes
        public let archiveSize: Int64
        /// List of profile filenames included
        public let profileNames: [String]
    }

    /// Encrypts provisioning profiles into an encrypted archive
    ///
    /// - Parameters:
    ///   - sourcePath: Path to source directory containing .mobileprovision files
    ///   - archivePath: Path where encrypted archive will be created
    ///   - password: Optional password (if nil, will be retrieved from ENV/Keychain)
    /// - Returns: EncryptResult with details about the operation
    /// - Throws: Various `ProvisionError` cases
    public func encryptProfiles(
        sourcePath: String,
        archivePath: String,
        password: String? = nil
    ) throws -> EncryptResult {
        let resolvedSourcePath = resolvePath(sourcePath)
        let resolvedArchivePath = resolvePath(archivePath)

        // 1. Verify source directory exists
        guard fileManager.fileExists(atPath: resolvedSourcePath) else {
            throw ProvisionError.sourceDirectoryNotFound(path: sourcePath)
        }

        // 2. Find all .mobileprovision files
        let profiles = try findProfiles(in: resolvedSourcePath)
        guard !profiles.isEmpty else {
            throw ProvisionError.noProfilesFound(path: sourcePath)
        }

        // 3. Get password
        let pwd = try password ?? getPassword()

        // 4. Create staging directory
        try createStagingDirectory()

        // 5. Create deterministic ZIP archive
        let zipPath = (stagingDirectory as NSString).appendingPathComponent("profiles.zip")
        try createDeterministicZip(profiles: profiles, sourcePath: resolvedSourcePath, outputPath: zipPath)

        // 6. Encrypt the ZIP archive
        try ensureArchiveDirectoryExists(for: resolvedArchivePath)
        try encryptFile(inputPath: zipPath, outputPath: resolvedArchivePath, password: pwd)

        // 7. Clean up staging files
        try? fileManager.removeItem(atPath: zipPath)

        // 8. Get archive size (skip in dry-run mode since file doesn't exist)
        let archiveSize: Int64 = executor.dryRun ? 0 : try getFileSize(path: resolvedArchivePath)

        return EncryptResult(
            profileCount: profiles.count,
            archivePath: archivePath,
            archiveSize: archiveSize,
            profileNames: profiles
        )
    }

    // MARK: - Decrypt Profiles

    /// Result of decrypting profiles
    public struct DecryptResult: Sendable {
        /// Number of profiles extracted
        public let profileCount: Int
        /// Path where profiles were extracted
        public let extractPath: String
        /// List of extracted profile filenames
        public let profileNames: [String]
    }

    /// Decrypts an encrypted archive and extracts provisioning profiles
    ///
    /// - Parameters:
    ///   - archivePath: Path to the encrypted archive
    ///   - extractPath: Path where profiles will be extracted
    ///   - password: Optional password (if nil, will be retrieved from ENV/Keychain)
    /// - Returns: DecryptResult with details about the operation
    /// - Throws: Various `ProvisionError` cases
    public func decryptProfiles(
        archivePath: String,
        extractPath: String,
        password: String? = nil
    ) throws -> DecryptResult {
        let resolvedArchivePath = resolvePath(archivePath)
        let resolvedExtractPath = resolvePath(extractPath)

        // 1. Verify archive exists
        guard fileManager.fileExists(atPath: resolvedArchivePath) else {
            throw ProvisionError.archiveNotFound(path: archivePath)
        }

        // 2. Get password
        let pwd = try password ?? getPassword()

        // 3. Create staging directory
        try createStagingDirectory()

        // 4. Decrypt the archive
        let zipPath = (stagingDirectory as NSString).appendingPathComponent("profiles.zip")
        try decryptFile(inputPath: resolvedArchivePath, outputPath: zipPath, password: pwd)

        // 5. Create extract directory
        try fileManager.createDirectory(atPath: resolvedExtractPath, withIntermediateDirectories: true)

        // 6. Extract the ZIP archive
        try extractZip(zipPath: zipPath, destinationPath: resolvedExtractPath)

        // 7. Clean up staging files
        try? fileManager.removeItem(atPath: zipPath)

        // 8. List extracted profiles
        let profiles = try findProfiles(in: resolvedExtractPath)

        return DecryptResult(
            profileCount: profiles.count,
            extractPath: extractPath,
            profileNames: profiles
        )
    }

    // MARK: - List Profiles

    /// Lists profiles in an encrypted archive without fully extracting
    ///
    /// - Parameters:
    ///   - archivePath: Path to the encrypted archive
    ///   - password: Optional password (if nil, will be retrieved from ENV/Keychain)
    /// - Returns: Array of profile filenames in the archive
    /// - Throws: Various `ProvisionError` cases
    public func listProfiles(
        archivePath: String,
        password: String? = nil
    ) throws -> [String] {
        let resolvedArchivePath = resolvePath(archivePath)

        // 1. Verify archive exists
        guard fileManager.fileExists(atPath: resolvedArchivePath) else {
            throw ProvisionError.archiveNotFound(path: archivePath)
        }

        // 2. Get password
        let pwd = try password ?? getPassword()

        // 3. Create staging directory
        try createStagingDirectory()

        // 4. Decrypt the archive
        let zipPath = (stagingDirectory as NSString).appendingPathComponent("profiles.zip")
        try decryptFile(inputPath: resolvedArchivePath, outputPath: zipPath, password: pwd)

        // 5. List ZIP contents
        let result = try executor.executeReadOnly("/usr/bin/unzip -Z1 '\(zipPath)'")
        let profiles = result.output
            .components(separatedBy: "\n")
            .filter { $0.hasSuffix(".mobileprovision") }
            .map { ($0 as NSString).lastPathComponent }

        // 6. Clean up staging files
        try? fileManager.removeItem(atPath: zipPath)

        return profiles
    }

    // MARK: - Install Profiles

    /// Result of installing profiles
    public struct InstallResult: Sendable {
        /// Number of profiles installed
        public let installedCount: Int
        /// Number of profiles skipped (already installed)
        public let skippedCount: Int
        /// List of installed profile filenames
        public let installedProfiles: [String]
        /// List of skipped profile filenames
        public let skippedProfiles: [String]
    }

    /// Installs decrypted profiles to the system provisioning profiles directory
    ///
    /// - Parameter extractPath: Path to the directory containing decrypted profiles
    /// - Returns: InstallResult with details about the operation
    /// - Throws: Various `ProvisionError` cases
    public func installProfiles(extractPath: String) throws -> InstallResult {
        let resolvedExtractPath = resolvePath(extractPath)

        // 1. Verify extract directory exists
        guard fileManager.fileExists(atPath: resolvedExtractPath) else {
            throw ProvisionError.sourceDirectoryNotFound(path: extractPath)
        }

        // 2. Create system profiles directory if needed
        try fileManager.createDirectory(atPath: systemProfilesPath, withIntermediateDirectories: true)

        // 3. Find profiles to install
        let profiles = try findProfiles(in: resolvedExtractPath)
        guard !profiles.isEmpty else {
            throw ProvisionError.noProfilesFound(path: extractPath)
        }

        // 4. Install each profile
        var installedProfiles: [String] = []
        var skippedProfiles: [String] = []

        for profile in profiles {
            let sourcePath = (resolvedExtractPath as NSString).appendingPathComponent(profile)
            let destPath = (systemProfilesPath as NSString).appendingPathComponent(profile)

            // Check if profile already exists with same content
            if fileManager.fileExists(atPath: destPath) {
                if filesAreIdentical(sourcePath, destPath) {
                    skippedProfiles.append(profile)
                    continue
                }
            }

            // Copy profile
            do {
                if fileManager.fileExists(atPath: destPath) {
                    try fileManager.removeItem(atPath: destPath)
                }
                try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                installedProfiles.append(profile)
            } catch {
                throw ProvisionError.installFailed(reason: "Failed to copy \(profile): \(error.localizedDescription)")
            }
        }

        return InstallResult(
            installedCount: installedProfiles.count,
            skippedCount: skippedProfiles.count,
            installedProfiles: installedProfiles,
            skippedProfiles: skippedProfiles
        )
    }

    // MARK: - Cleanup

    /// Result of cleanup operation
    public struct CleanupResult: Sendable {
        /// Number of files removed
        public let removedCount: Int
        /// List of removed paths
        public let removedPaths: [String]
    }

    /// Removes decrypted profiles and staging files
    ///
    /// - Parameter extractPath: Path to the decrypted profiles directory
    /// - Returns: CleanupResult with details about removed files
    public func cleanup(extractPath: String) throws -> CleanupResult {
        var removedPaths: [String] = []

        // Remove extract directory
        let resolvedExtractPath = resolvePath(extractPath)
        if fileManager.fileExists(atPath: resolvedExtractPath) {
            try fileManager.removeItem(atPath: resolvedExtractPath)
            removedPaths.append(extractPath)
        }

        // Remove staging directory
        if fileManager.fileExists(atPath: stagingDirectory) {
            try fileManager.removeItem(atPath: stagingDirectory)
            removedPaths.append("tmp/provision")
        }

        return CleanupResult(
            removedCount: removedPaths.count,
            removedPaths: removedPaths
        )
    }

    // MARK: - Password Management

    /// Gets the provision password from ENV, Keychain, or interactive prompt
    ///
    /// Priority:
    /// 1. Environment variable: PROVISION_PASSWORD
    /// 2. macOS Keychain
    /// 3. Interactive prompt (if enabled and TTY available)
    ///
    /// - Returns: The password
    /// - Throws: `ProvisionError.passwordNotFound` if password cannot be found
    public func getPassword() throws -> String {
        // Priority 1: Environment variable
        if let pwd = ProcessInfo.processInfo.environment["PROVISION_PASSWORD"], !pwd.isEmpty {
            return pwd
        }

        // Priority 2: Keychain
        if let pwd = try? getPasswordFromKeychain() {
            return pwd
        }

        // Priority 3: Interactive prompt
        if interactiveEnabled && isInteractive() {
            return try promptForPassword()
        }

        throw ProvisionError.passwordNotFound
    }

    /// Stores a password in the keychain
    ///
    /// - Parameter password: The password to store
    /// - Throws: Error if keychain operation fails
    public func setPassword(_ password: String) throws {
        try setPasswordInKeychain(password)
    }

    // MARK: - Private Methods - OpenSSL Operations

    /// Encrypts a file using OpenSSL AES-256-CBC with PBKDF2
    private func encryptFile(inputPath: String, outputPath: String, password: String) throws {
        // Verify openssl exists
        guard fileManager.fileExists(atPath: "/usr/bin/openssl") else {
            throw ProvisionError.opensslNotFound
        }

        // OpenSSL uses -pass env:PASS for password input (avoids command line exposure)
        let result = try executor.execute(
            "/usr/bin/openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -md sha256 " +
            "-in '\(inputPath)' -out '\(outputPath)' -pass env:PASS",
            environment: ["PASS": password]
        )

        if result.exitCode != 0 {
            throw ProvisionError.encryptionFailed(reason: result.error.isEmpty ? "OpenSSL encryption failed" : result.error)
        }
    }

    /// Decrypts a file using OpenSSL AES-256-CBC
    private func decryptFile(inputPath: String, outputPath: String, password: String) throws {
        guard fileManager.fileExists(atPath: "/usr/bin/openssl") else {
            throw ProvisionError.opensslNotFound
        }

        let result = try executor.execute(
            "/usr/bin/openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -md sha256 " +
            "-in '\(inputPath)' -out '\(outputPath)' -pass env:PASS",
            environment: ["PASS": password]
        )

        if result.exitCode != 0 {
            // Check for common decryption errors
            if result.error.contains("bad decrypt") || result.error.contains("wrong final block") {
                throw ProvisionError.wrongPassword
            }
            throw ProvisionError.decryptionFailed(reason: result.error.isEmpty ? "OpenSSL decryption failed" : result.error)
        }
    }

    // MARK: - Private Methods - ZIP Operations

    /// Creates a deterministic ZIP archive from profiles
    private func createDeterministicZip(profiles: [String], sourcePath: String, outputPath: String) throws {
        // Remove existing zip if any
        try? fileManager.removeItem(atPath: outputPath)

        // Sort profiles for deterministic order
        let sortedProfiles = profiles.sorted()

        // Create zip command with files in sorted order
        // Using -X to exclude extra file attributes for determinism
        let profilePaths = sortedProfiles
            .map { "'\(($0 as NSString).lastPathComponent)'" }
            .joined(separator: " ")

        // Change to source directory to create flat zip
        let zipCommand = "cd '\(sourcePath)' && /usr/bin/zip -X -q '\(outputPath)' \(profilePaths)"
        let result = try executor.execute(zipCommand)

        if result.exitCode != 0 {
            throw ProvisionError.zipFailed(reason: result.error.isEmpty ? "ZIP creation failed" : result.error)
        }
    }

    /// Extracts a ZIP archive to a destination directory
    private func extractZip(zipPath: String, destinationPath: String) throws {
        let result = try executor.execute("/usr/bin/unzip -o -q '\(zipPath)' -d '\(destinationPath)'")

        if result.exitCode != 0 {
            throw ProvisionError.unzipFailed(reason: result.error.isEmpty ? "ZIP extraction failed" : result.error)
        }
    }

    // MARK: - Private Methods - File Operations

    /// Finds all .mobileprovision files in a directory
    private func findProfiles(in path: String) throws -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }

        return contents.filter { $0.hasSuffix(".mobileprovision") }.sorted()
    }

    /// Creates the staging directory if it doesn't exist
    private func createStagingDirectory() throws {
        if !fileManager.fileExists(atPath: stagingDirectory) {
            try fileManager.createDirectory(atPath: stagingDirectory, withIntermediateDirectories: true)
        }
    }

    /// Ensures the directory for the archive exists
    private func ensureArchiveDirectoryExists(for path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
    }

    /// Gets file size in bytes
    private func getFileSize(path: String) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Checks if two files have identical content
    private func filesAreIdentical(_ path1: String, _ path2: String) -> Bool {
        guard let data1 = fileManager.contents(atPath: path1),
              let data2 = fileManager.contents(atPath: path2) else {
            return false
        }
        return data1 == data2
    }

    /// Resolves a relative path to an absolute path
    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDirectory as NSString).appendingPathComponent(path)
    }

    // MARK: - Private Methods - Keychain Operations

    /// Checks if current session is interactive (has TTY)
    private func isInteractive() -> Bool {
        return isatty(STDIN_FILENO) != 0
    }

    /// Prompts user for password interactively (password is not echoed)
    private func promptForPassword() throws -> String {
        print("")
        print("Provision password not found.")
        print("")
        print("The password was not found in:")
        print("  1. Environment variable: PROVISION_PASSWORD")
        print("  2. macOS Keychain (service: \(keychainServiceName))")
        print("")

        // Use getpass() to read password without echoing to terminal
        guard let cPassword = getpass("Enter provision password: "),
              let pwd = String(cString: cPassword, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pwd.isEmpty else {
            throw ProvisionError.passwordNotFound
        }

        // Ask if user wants to save to keychain
        print("Save to keychain for future use? [Y/n]: ", terminator: "")
        let saveResponse = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "y"

        if saveResponse.isEmpty || saveResponse == "y" || saveResponse == "yes" {
            try setPasswordInKeychain(pwd)
            print("✓ Password saved to keychain")
        }

        return pwd
    }

    /// Gets password from keychain
    private func getPasswordFromKeychain() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: "provision",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let passwordData = item as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw ProvisionError.passwordNotFound
        }

        return password
    }

    /// Sets password in keychain
    private func setPasswordInKeychain(_ password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw ProvisionError.encryptionFailed(reason: "Failed to encode password")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: "provision"
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
                throw ProvisionError.encryptionFailed(reason: "Failed to save password to keychain")
            }
        } else if updateStatus != errSecSuccess {
            throw ProvisionError.encryptionFailed(reason: "Failed to update password in keychain")
        }
    }
}
