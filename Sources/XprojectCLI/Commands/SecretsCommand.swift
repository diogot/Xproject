//
// SecretsCommand.swift
// Xproject
//
// Commands for managing encrypted secrets
//

import ArgumentParser
import Foundation
import Xproject

struct SecretsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "secrets",
        abstract: "Manage encrypted secrets",
        discussion: """
        Secret management commands for encrypting, decrypting, and generating
        Swift code from EJSON-encrypted secrets.

        Secrets are protected with dual-layer security:
        1. EJSON encryption (at-rest) - Asymmetric encryption in repository
        2. XOR obfuscation (in-binary) - Prevents `strings` extraction from compiled apps

        Common workflow:
          1. xp secrets show dev           # View encrypted file info
          2. xp secrets generate dev       # Generate obfuscated Swift code
          3. xp secrets encrypt            # Encrypt all environments
        """,
        subcommands: [
            SecretsGenerateKeysCommand.self,
            SecretsGenerateCommand.self,
            SecretsEncryptCommand.self,
            SecretsShowCommand.self,
            SecretsDecryptCommand.self,
            SecretsValidateCommand.self
        ]
    )
}

// MARK: - Generate Keys Command

struct SecretsGenerateKeysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-keys",
        abstract: "Generate new EJSON keypair for an environment",
        discussion: """
        Creates a new EJSON keypair and initializes the keys.ejson file for an environment.

        The public key is stored in the generated file (safe to commit to git).
        The private key is displayed once and must be saved securely.

        For CI/CD, set the private key as an environment variable:
          export EJSON_PRIVATE_KEY_DEV="<private-key>"

        For local development, use --save-to-keychain to store in macOS Keychain.
        """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Environment name (e.g., dev, staging, production)")
    var environment: String

    @Flag(name: .long, help: "Save private key to macOS Keychain")
    var saveToKeychain: Bool = false

    @Flag(name: .long, help: "Overwrite existing keys.ejson file")
    var force: Bool = false

    @Flag(name: .long, help: "Show what would be done without making changes")
    var dryRun: Bool = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        // Get configuration for app name (needed for keychain service)
        let config = try configService.configuration
        let ejsonService = EJSONService(workingDirectory: workingDir)

        // Check if environment already exists
        let envDir = "env/\(environment)"
        let ejsonPath = "\(envDir)/keys.ejson"
        let fullEnvDir = (workingDir as NSString).appendingPathComponent(envDir)
        let fullEjsonPath = (workingDir as NSString).appendingPathComponent(ejsonPath)

        if FileManager.default.fileExists(atPath: fullEjsonPath) && !force {
            throw SecretError.invalidSecretConfiguration(
                reason: """
                    Environment '\(environment)' already exists at \(ejsonPath).
                    Use --force to overwrite.
                    """
            )
        }

        // Generate keypair
        let keyPair = try ejsonService.generateKeyPair()

        if dryRun {
            print("Would create: \(ejsonPath)")
            print("Would generate new EJSON keypair")
            if saveToKeychain {
                print("Would save private key to macOS Keychain")
            }
            return
        }

        // Create directory if needed
        try FileManager.default.createDirectory(
            atPath: fullEnvDir,
            withIntermediateDirectories: true
        )

        // Write keys.ejson with public key
        let ejsonContent = """
            {
              "_public_key": "\(keyPair.publicKey)"
            }
            """
        try ejsonContent.write(toFile: fullEjsonPath, atomically: true, encoding: .utf8)

        // Save to keychain if requested
        if saveToKeychain {
            let keychainService = KeychainService(appName: config.appName)
            try keychainService.setEJSONPrivateKey(keyPair.privateKey, environment: environment)
        }

        // Display results
        print("✓ Generated EJSON keypair for '\(environment)'")
        print("")
        print("Public key (committed to git):")
        print("  \(keyPair.publicKey)")
        print("")
        print("Private key (SAVE THIS SECURELY - shown only once):")
        print("  \(keyPair.privateKey)")
        print("")
        print("Created: \(ejsonPath)")
        print("")
        print("To use this environment:")
        print("  • CI/CD: export EJSON_PRIVATE_KEY_\(environment.uppercased())=\"\(keyPair.privateKey)\"")
        if saveToKeychain {
            print("  • Local: Private key saved to macOS Keychain ✓")
        } else {
            print("  • Local: Run again with --save-to-keychain to store in Keychain")
        }
    }
}

// MARK: - Generate Command

struct SecretsGenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate obfuscated Swift code from secrets"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name (e.g., dev, staging, production)")
    var environment: String
    @Flag(name: .long, help: "Show what would be generated without writing files")
    var dryRun = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )

        // Get configuration
        let config = try configService.configuration
        let keychainService = KeychainService(appName: config.appName)
        let ejsonService = EJSONService(workingDirectory: workingDir)
        guard let secretsConfig = config.secrets else {
            throw SecretError.secretsNotEnabled
        }

        guard let swiftGeneration = secretsConfig.swiftGeneration else {
            throw SecretError.invalidSecretConfiguration(reason: "No swift_generation configured")
        }

        // Get private key
        let privateKey = try keychainService.getEJSONPrivateKey(environment: environment)

        // Decrypt secrets
        let ejsonPath = "env/\(environment)/keys.ejson"
        let secrets = try ejsonService.decryptFile(path: ejsonPath, privateKey: privateKey)

        // Offer to save key to keychain after successful decryption
        try keychainService.promptToSavePrivateKey(privateKey, environment: environment)

        // Filter to string values only
        let stringSecrets = secrets.compactMapValues { $0 as? String }

        // Generate Swift files
        for output in swiftGeneration.outputs {
            let swiftCode = AppKeysTemplate.generateAppKeys(
                secrets: stringSecrets,
                prefixes: output.prefixes,
                environment: environment
            )

            if dryRun {
                print("Would generate: \(output.path)")
                print(swiftCode)
                print("")
            } else {
                let fullPath = (workingDir as NSString).appendingPathComponent(output.path)
                let directory = (fullPath as NSString).deletingLastPathComponent

                // Create directory if needed
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )

                // Write file
                try swiftCode.write(toFile: fullPath, atomically: true, encoding: .utf8)
                print("Generated: \(output.path)")
            }
        }

        if !dryRun {
            print("\n✓ Generated \(swiftGeneration.outputs.count) AppKeys file(s) for \(environment)")
        }
    }
}

// MARK: - Encrypt Command

struct SecretsEncryptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encrypt",
        abstract: "Encrypt EJSON files"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name (optional - encrypts all if not specified)")
    var environment: String?
    @Flag(name: .long, help: "Show what would be encrypted without modifying files")
    var dryRun = false

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let ejsonService = EJSONService(workingDirectory: workingDir)

        if let environment = environment {
            // Encrypt specific environment
            let ejsonPath = "env/\(environment)/keys.ejson"

            if dryRun {
                print("Would encrypt: \(ejsonPath)")
                let publicKey = try ejsonService.extractPublicKey(path: ejsonPath)
                print("Public key: \(publicKey)")
            } else {
                try ejsonService.encryptFile(path: ejsonPath)
                print("✓ Encrypted: \(ejsonPath)")
            }
        } else {
            // Encrypt all environments
            if dryRun {
                let envDir = (workingDir as NSString).appendingPathComponent("env")
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: envDir) else {
                    print("No environments found")
                    return
                }

                for item in contents.sorted() {
                    let keysPath = "env/\(item)/keys.ejson"
                    let fullPath = (workingDir as NSString).appendingPathComponent(keysPath)
                    if FileManager.default.fileExists(atPath: fullPath) {
                        print("Would encrypt: \(keysPath)")
                    }
                }
            } else {
                let encrypted = try ejsonService.encryptAllEnvironments()
                if encrypted.isEmpty {
                    print("No EJSON files found to encrypt")
                } else {
                    for file in encrypted.sorted() {
                        print("✓ Encrypted: \(file)")
                    }
                    print("\n✓ Encrypted \(encrypted.count) file(s)")
                }
            }
        }
    }
}

// MARK: - Show Command

struct SecretsShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display encrypted file information"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name")
    var environment: String

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let ejsonService = EJSONService(workingDirectory: workingDir)

        let ejsonPath = "env/\(environment)/keys.ejson"
        let fullPath = (workingDir as NSString).appendingPathComponent(ejsonPath)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw SecretError.ejsonFileNotFound(path: fullPath)
        }

        // Extract public key
        let publicKey = try ejsonService.extractPublicKey(path: ejsonPath)

        // Read file to count keys
        let data = try Data(contentsOf: URL(fileURLWithPath: fullPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let secretCount = json.keys.filter { $0 != "_public_key" }.count

        print("EJSON File: \(ejsonPath)")
        print("Public Key: \(publicKey)")
        print("Secret Count: \(secretCount)")

        if secretCount > 0 {
            print("\nSecret Keys:")
            for key in json.keys.sorted() where key != "_public_key" {
                let value = json[key] as? String ?? ""
                let isEncrypted = value.hasPrefix("EJ[1:")
                let status = isEncrypted ? "🔒 encrypted" : "⚠️  plaintext"
                print("  - \(key) (\(status))")
            }
        }
    }
}

// MARK: - Decrypt Command

struct SecretsDecryptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decrypt",
        abstract: "Decrypt and display secrets (development only)"
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name")
    var environment: String

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let configService = ConfigurationService(
            workingDirectory: workingDir,
            customConfigPath: globalOptions.config
        )
        let config = try configService.configuration
        let keychainService = KeychainService(appName: config.appName)
        let ejsonService = EJSONService(workingDirectory: workingDir)

        // Get private key
        let privateKey = try keychainService.getEJSONPrivateKey(environment: environment)

        // Decrypt secrets
        let ejsonPath = "env/\(environment)/keys.ejson"
        let secrets = try ejsonService.decryptFile(path: ejsonPath, privateKey: privateKey)

        // Offer to save key to keychain after successful decryption
        try keychainService.promptToSavePrivateKey(privateKey, environment: environment)

        print("Decrypted secrets for \(environment):")
        print("")

        for (key, value) in secrets.sorted(by: { $0.key < $1.key }) {
            if key == "_public_key" {
                continue
            }
            print("\(key):")
            print("  \(value)")
            print("")
        }
    }
}

// MARK: - Validate Command

struct SecretsValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate EJSON files",
        discussion: """
        Validates all EJSON files in environment directories without decryption.

        Checks:
        - File exists and contains valid JSON
        - Public key is present and has valid format (64-char hex)
        - Reports encryption status of each secret (warning if plaintext)

        This command does NOT require the private key.
        """
    )

    @OptionGroup var globalOptions: GlobalOptions
    @Argument(help: "Environment name (optional - validates all if not specified)")
    var environment: String?

    func run() async throws {
        let workingDir = globalOptions.resolvedWorkingDirectory
        let ejsonService = EJSONService(workingDirectory: workingDir)

        if let environment = environment {
            // Validate specific environment
            let ejsonPath = "env/\(environment)/keys.ejson"
            let result = ejsonService.validateFile(path: ejsonPath)
            printValidationResult(environment: environment, path: ejsonPath, result: result)

            if !result.isValid {
                throw ExitCode.failure
            }
        } else {
            // Validate all environments
            let results = ejsonService.validateAllEnvironments()

            if results.isEmpty {
                print("No EJSON files found in env/*/keys.ejson")
                return
            }

            var hasErrors = false
            for (environment, result) in results.sorted(by: { $0.key < $1.key }) {
                let ejsonPath = "env/\(environment)/keys.ejson"
                printValidationResult(environment: environment, path: ejsonPath, result: result)

                if !result.isValid {
                    hasErrors = true
                }
                print("")
            }

            if hasErrors {
                print("✗ Validation failed for one or more environments")
                throw ExitCode.failure
            } else {
                print("✓ All EJSON files are valid")
            }
        }
    }

    private func printValidationResult(
        environment: String,
        path: String,
        result: EJSONService.ValidationResult
    ) {
        let statusIcon = result.isValid ? "✓" : "✗"
        print("\(statusIcon) \(environment) (\(path))")

        if let publicKey = result.publicKey {
            print("  Public Key: \(publicKey.prefix(16))...")
        }

        print("  Secrets: \(result.secretCount) total, \(result.encryptedCount) encrypted, \(result.plaintextCount) plaintext")

        // Print issues
        let errors = result.issues.filter { $0.severity == .error }
        let warnings = result.issues.filter { $0.severity == .warning }

        for issue in errors {
            print("  ✗ ERROR: \(issue.message)")
        }

        for issue in warnings {
            print("  ⚠ WARNING: \(issue.message)")
        }
    }
}
