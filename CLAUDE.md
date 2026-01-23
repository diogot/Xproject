# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Intent

This repository is undergoing a migration from Ruby Rake to a modern Swift command line tool called **Xproject**. The existing Ruby rakelib serves as a reference implementation that we are incrementally migrating to Swift, taking the opportunity to:

- **Modernize configuration**: Move from YAML to more flexible formats (TOML, Swift configs)
- **Improve type safety**: Leverage Swift's type system for compile-time validation
- **Enhance extensibility**: Design a plugin-based architecture for easy feature additions
- **Better developer experience**: Create more intuitive commands and helpful error messages
- **Reduce dependencies**: Eliminate Ruby/gem dependencies for easier CI/CD setup

**Important**: The current Ruby rakelib should be used only as reference for understanding existing functionality. All new development should focus on the Swift Xproject tool, migrating features one by one while improving upon the original design.

## Before Starting a New Feature

**Remember to bump the CLI version!** Before starting work on a new feature or bug fix that will be released, update the `VERSION` file at the project root with the new version number. This ensures:
- The release workflow can create a new release when changes are merged
- The `xp --version` command reports the correct version
- Version validation passes in CI

```bash
# Check current version
cat VERSION

# Update to new version
echo "1.1.0" > VERSION
```

## Current Implementation Status

### Completed Features
- ✅ **Swift Package Manager structure**: Package.swift with Xproject library and XprojectCLI executable
- ✅ **Type-safe configuration system**: YAML loading with Codable structs, validation, and layered overrides
- ✅ **Setup command**: Homebrew formula installation (deprecated bundler/cocoapods/submodules removed)
- ✅ **Build command**: Complete implementation for building Xcode projects for testing
- ✅ **Test command**: Full test orchestration with multi-scheme and multi-destination support
- ✅ **Release command**: Complete implementation for iOS/tvOS app archiving, IPA generation, and App Store upload
- ✅ **Working directory support**: Run commands from any directory with `-C/--working-directory`
- ✅ **Multi-scheme and multi-destination testing**: Run tests across multiple iOS simulators
- ✅ **Custom configuration files**: Use `--config` option to specify project-specific configs
- ✅ **Dry-run mode**: Preview operations without executing them (`--dry-run`)
- ✅ **Verbose mode**: Show detailed command output with `--verbose`
- ✅ **Enhanced error handling**: Clear error messages with config file context
- ✅ **Legacy compatibility**: Works with existing rake-config.yml files
- ✅ **Type-safe configuration**: Swift Codable structs with validation
- ✅ **Homebrew integration**: Automated tool installation and updates
- ✅ **Clean architecture**: Separated CLI and business logic with explicit working directory handling
- ✅ **Improved CLI output formatting**: Clear info blocks showing working directory and configuration at command start, with environment variables displayed in structured format
- ✅ **Environment management**: Complete environment system with xcconfig generation, variable mapping, and multi-environment support
- ✅ **Version management**: Automated version bumping (patch/minor/major), build numbers from git commits, and git tagging
- ✅ **Git operations**: Automated version commit, tag creation with environment support, and push to remote
- ✅ **Secret management**: Dual-layer security (EJSON encryption + XOR obfuscation) for API keys with binary protection
- ✅ **Provision management**: Encrypted provisioning profile storage and installation for CI/CD
- ✅ **PR Report integration**: Post build/test results to GitHub PRs via Checks API with xcresult parsing

### Architecture Overview
**Targets:**
- `XprojectCLI`: CLI layer using ArgumentParser, calls into Xproject library
- `Xproject`: Core business logic library (configuration, services, utilities) - no CLI dependencies
- `XprojectTests`: Test suite for core library

**Key Services:**
- `ConfigurationService`: Thread-safe singleton for loading and caching YAML configs with custom config file support
- `SetupService`: Handles project setup (currently Homebrew only)
- `BuildService`: Handles building for tests with Xcode discovery
- `TestService`: Orchestrates test workflows including build and test phases across multiple schemes/destinations
- `ReleaseService`: Orchestrates release workflow (archive → IPA generation → App Store upload)
- `CleanService`: Removes build artifacts and test reports directories
- `EnvironmentService`: Manages environment configurations, xcconfig generation, and variable mapping
- `VersionService`: Handles version bumping and build number calculation from git commits
- `GitService`: Git operations (commit, tag, push) with safety checks
- `EJSONService`: EJSON encryption/decryption wrapper around swift-ejson library
- `KeychainService`: macOS Keychain integration for secure private key storage
- `ProvisionService`: Provisioning profile encryption/decryption and installation
- `PRReportService`: Parses xcresult bundles and posts results to GitHub PRs via Checks API

**Key Utilities:**
- `OutputFormatter`: Consistent formatting for CLI output with info blocks and structured display
- `CommandExecutor`: Utility for executing shell commands safely with dry-run support and executeReadOnly for discovery operations
- `NestedDictionary`: Dot notation access for nested YAML structures (e.g., "apps.ios.bundle_identifier")
- `StringObfuscator`: XOR-based obfuscation for preventing binary string extraction

### Development Commands
```bash
# Build and test the Xproject Swift package itself
swift build            # Build the project
swift build -c release # Build for release
swift test             # Run all tests
swift run xp           # Run the CLI tool directly

# Install for development
swift build -c release
cp .build/release/xp /usr/local/bin/  # Optional: install to PATH
```

### Available Commands
```bash
# Global options available on all commands
-C, --working-directory <path>  # Working directory for the command (default: current directory)
-c, --config <path>             # Specify custom configuration file (auto-discovers Xproject.yml, rake-config.yml by default)
-v, --verbose                   # Show detailed output and commands being executed
--dry-run                       # Show what would be done without executing (available on most commands)

# Core commands
xp setup           # Install/update Homebrew formulas from config
xp config show     # Display current configuration
xp config validate # Validate configuration files with comprehensive checks
xp build           # Build for testing (supports --scheme, --clean, --destination)
xp test            # Run tests (supports --scheme, --clean, --skip-build, --destination)
xp release         # Create release builds (archive, IPA, upload with --archive-only, --skip-upload, --upload-only)
xp clean           # Remove build artifacts and test reports (supports --dry-run)
xp env list        # List available environments
xp env show        # Show environment variables (current or specific)
xp env current     # Show currently activated environment
xp env load    # Load an environment and generate xcconfig files
xp env validate    # Validate environment configuration
xp secrets generate <env>  # Generate obfuscated AppKeys.swift
xp secrets encrypt [env]   # Encrypt EJSON files
xp secrets show <env>      # Display encrypted file info
xp secrets decrypt <env>   # Decrypt and display (dev only)
xp secrets validate [env]  # Validate EJSON file structure
xp provision encrypt       # Encrypt provisioning profiles
xp provision decrypt       # Decrypt provisioning profile archive
xp provision list          # List profiles in encrypted archive
xp provision install       # Install profiles to system
xp provision cleanup       # Remove decrypted profiles
xp version show            # Show current version
xp version bump <level>    # Bump version (patch/minor/major)
xp version commit          # Commit version changes
xp version tag             # Create version tag
xp version push            # Push to remote with tags
xp pr-report               # Post build/test results to GitHub PR (auto-discovers xcresult bundles)
xp pr-report --xcresult <path>  # Report specific xcresult bundle
xp pr-report --build-only  # Report only build warnings/errors
xp pr-report --test-only   # Report only test failures
xp pr-report --dry-run     # Preview without posting to GitHub

# Examples
xp -C /path/to/project config show
xp --working-directory MyProject build --scheme MyApp --clean
xp test --config my-config.yml --scheme MyApp --clean --dry-run
xp release production-ios
xp release dev-ios --archive-only --dry-run
xp setup --dry-run
xp clean --dry-run
xp config --config custom.yml validate
xp env list
xp env load dev --dry-run
xp env load production
xp env show dev
xp secrets generate dev
xp provision encrypt
xp provision decrypt
xp provision install
xp version bump patch
xp version tag --environment production
xp version push
xp pr-report --dry-run
xp pr-report --check-name "iOS Tests"
```

## Environment Management

Xproject includes a complete environment management system for handling multiple deployment environments (dev, staging, production, etc.) with automatic xcconfig file generation.

### Overview

The environment system allows you to:
- Define multiple environments (dev, staging, production, etc.)
- Generate environment-specific `.xcconfig` files automatically
- Manage configuration variables using YAML
- Support multiple targets with bundle ID suffixes
- Per-configuration variable overrides (debug vs release)

### Directory Structure

```
YourProject/
├── env/
│   ├── config.yml              # Environment system configuration
│   ├── .current                # Currently active environment (gitignored)
│   ├── dev/
│   │   └── env.yml            # Development environment variables
│   ├── staging/
│   │   └── env.yml            # Staging environment variables
│   └── production/
│       └── env.yml            # Production environment variables
├── YourApp/
│   └── Config/                 # Generated xcconfig files (gitignored)
│       ├── YourApp.debug.xcconfig
│       └── YourApp.release.xcconfig
└── Xproject.yml                # Project configuration
```

### Quick Start

1. **Create env/config.yml:**
   ```yaml
   targets:
     - name: MyApp
       xcconfig_path: MyApp/Config
       shared_variables:
         PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_identifier
         BUNDLE_DISPLAY_NAME: apps.display_name
         API_URL: api_url
       configurations:
         debug: {}
         release:
           variables:
             PROVISIONING_PROFILE_SPECIFIER: apps.ios.provision_profile
   ```

2. **Create environment files (e.g., env/dev/env.yml):**
   ```yaml
   environment_name: development
   api_url: https://dev-api.example.com

   apps:
     bundle_identifier: com.example.myapp.dev
     display_name: MyApp Dev
     ios:
       app_icon_name: AppIcon
       provision_profile: Development
   ```

3. **Activate environment:**
   ```bash
   xp env load dev
   ```

### Key Features

- **Dot notation access**: Use paths like `apps.ios.bundle_identifier` to access nested YAML values
- **Bundle ID suffixes**: Automatically append suffixes for app extensions (`.widget`, `.notification-content`)
- **Configuration-specific variables**: Different variables for debug vs release builds
- **Swift code generation**: Type-safe Swift code from environment variables with prefix filtering and type inference
- **Validation**: Comprehensive validation of configuration and environment files
- **Dry-run support**: Preview xcconfig and Swift generation without writing files

### Swift Code Generation

The environment system can automatically generate type-safe Swift files:

```yaml
swift_generation:
  outputs:
    # Base class - automatically includes ALL root-level variables
    - path: MyApp/Generated/EnvironmentService.swift
      prefixes: []  # Empty - base type auto-includes root-level
      type: base
    # Extension - explicitly specify namespaces
    - path: MyApp/Generated/EnvironmentService+App.swift
      prefixes: [apps, features]
      type: extension
    # Extension in different module - imports base class module
    - path: MyAppKit/Generated/EnvironmentService+Kit.swift
      prefixes: [services]
      type: extension
      imports: [MyApp]
```

Features:
- **Base type auto-includes root-level**: Base class automatically includes all root-level variables
- **Namespace filtering**: Extensions filter by namespace (e.g., `apps`, `features`)
- **CamelCase conversion**: `bundle_identifier` → `bundleIdentifier`, `api_url` → `apiURL`
- **Type inference**: Automatic URL, String, Int, Bool detection
- **Base class or extension**: Generate standalone class or extend existing
- **URL handling**: Auto-detect URL properties by name suffix (`*URL`, `*Url`)
- **Cross-module imports**: Extensions can import modules containing the base class via `imports` option

Example generated code:
```swift
public final class EnvironmentService {
    public init() {}
    public let apiURL = url("https://dev-api.example.com")
    public let environmentName = "development"
}

extension EnvironmentService {
    public var bundleIdentifier: String { "com.example.app.dev" }
    public var iosAppIconName: String { "AppIcon" }
    public var debugMenu: Bool { true }
}
```

### Implementation Details

- **Models**: `EnvironmentConfig`, `SwiftGenerationConfig`, `SwiftOutputConfig` in Sources/Xproject/Models/EnvironmentConfig.swift
- **Service**: `EnvironmentService` in Sources/Xproject/Services/EnvironmentService.swift handles all environment operations
- **Templates**: `SwiftTemplates` in Sources/Xproject/Templates/SwiftTemplates.swift with embedded code generation
- **Utility**: `NestedDictionary` in Sources/Xproject/Utilities/NestedDictionary.swift provides dot notation access
- **Commands**: `EnvironmentCommand` in Sources/XprojectCLI/Commands/EnvironmentCommand.swift with 5 subcommands
- **Tests**: 28 dedicated tests (17 environment, 12 Swift generation) in Tests/XprojectTests/Services/ - 226 total tests passing

See `docs/environment-setup.md` for detailed setup guide and examples.

## Version Management

Xproject includes a complete version management system for handling semantic versioning, build numbers from git commits, and automated git tagging.

### Overview

The version management system allows you to:
- Bump semantic versions (major.minor.patch) using agvtool
- Calculate build numbers from git commit count with configurable offset
- Commit version changes automatically with `[skip ci]` prefix
- Create version tags in standardized format
- Push branches and tags to remote repositories

**Important**: The "target" parameter (e.g., "ios", "tvos") refers to a **configuration key** in `project_path`, not an Xcode build target. Each target maps to a specific `.xcodeproj` file, which may be in a subdirectory:

```yaml
project_path:
  ios: MyApp.xcodeproj          # Root-level project
  tvos: TV/TV.xcodeproj          # Subdirectory project
```

When you run `xp version bump patch ios`, agvtool updates **all Xcode targets** within `MyApp.xcodeproj`. Similarly, `xp version bump patch tvos` updates all targets in `TV/TV.xcodeproj`. This matches the behavior of Apple's agvtool, which operates on entire projects, not individual targets.

### Configuration

Add version configuration to your `Xproject.yml`:

```yaml
version:
  build_number_offset: -6854  # Offset for git commit count
  tag_format: "{env}-{target}/{version}-{build}"  # Optional custom format
```

### Available Commands

```bash
# Show current version and build
xp version show [target]

# Bump version (patch/minor/major)
xp version bump patch [target]          # 1.0.0 → 1.0.1
xp version bump minor [target]          # 1.0.0 → 1.1.0
xp version bump major [target]          # 1.0.0 → 2.0.0

# Commit version bump changes
xp version commit [target]              # Commits with [skip ci] prefix

# Create git tag
xp version tag [target]                 # Creates tag: ios/1.0.0-100
xp version tag [target] --environment production  # Creates tag: production-ios/1.0.0-100

# Push to remote
xp version push                         # Push current branch with tags
xp version push --remote upstream       # Push to specific remote

# All commands support --dry-run
xp version bump patch --dry-run
xp version tag --dry-run
```

### Common Workflow

```bash
# 1. Check current version
xp version show

# 2. Bump version
xp version bump patch

# 3. Commit changes
xp version commit

# 4. Create tag
xp version tag --environment production

# 5. Push to remote
xp version push
```

### Build Number Calculation

Build numbers are automatically calculated from git commit count:
- Gets current commit count with `git rev-list HEAD --count`
- Applies configured offset from `version.build_number_offset`
- Example: 7000 commits + offset -6854 = build number 146

### Tag Format

Tags follow the format: `[environment-]target/version-build`
- Without environment: `ios/1.0.0-146`
- With environment: `production-ios/1.0.0-146`

### Implementation Details

- **Models**: `Version`, `VersionConfiguration` in Sources/Xproject/Models/
- **Services**:
  - `VersionService` in Sources/Xproject/Services/VersionService.swift - Handles agvtool operations and build number calculation
  - `GitService` in Sources/Xproject/Services/GitService.swift - Handles git operations (commit, tag, push)
- **Commands**: `VersionCommand` in Sources/XprojectCLI/Commands/VersionCommand.swift with 5 subcommands
- **Tests**: 56 dedicated tests (19 Version + 17 VersionService + 20 GitService) - All passing

### Safety Features

- **Repository clean check**: Warns if uncommitted changes exist
- **Expected files validation**: Ensures only version-related files changed
- **Tag existence check**: Prevents duplicate tags
- **Dry-run mode**: Preview all operations before execution

## Secret Management

Xproject includes a complete secret management system for handling API keys and sensitive data with dual-layer security: EJSON encryption (at-rest) and XOR obfuscation (in-binary).

See `docs/secrets-management.md` for the complete user guide with setup instructions, CI/CD integration, and troubleshooting.

### Overview

The secret management system provides:
- **Dual-layer protection**: EJSON asymmetric encryption for repository storage + XOR obfuscation to prevent binary extraction
- **No plaintext in binaries**: Secrets stored as obfuscated byte arrays, defeating `strings` command
- **macOS Keychain integration**: Secure storage for EJSON private keys
- **CI/CD support**: Environment variable priority (`EJSON_PRIVATE_KEY_{ENV}` > `EJSON_PRIVATE_KEY` > Keychain)
- **Smart Swift generation**: Automatic CamelCase conversion, URL/API suffix handling, type inference
- **Automatic integration**: Secrets generated automatically during `xp env load`

### Configuration

Add to your `Xproject.yml`:

```yaml
secrets:
  swift_generation:
    outputs:
      - path: MyApp/Generated/AppKeys.swift
        prefixes: [all, ios]      # Filter secrets by prefix
      - path: MyTVApp/Generated/AppKeys.swift
        prefixes: [all, tvos]
```

### Directory Structure

```
YourProject/
├── env/
│   ├── dev/
│   │   ├── env.yml
│   │   └── keys.ejson          # Encrypted secrets
│   ├── production/
│   │   ├── env.yml
│   │   └── keys.ejson
└── MyApp/
    └── Generated/
        └── AppKeys.swift        # Generated obfuscated code (gitignored)
```

### Security Architecture

**Layer 1: EJSON Encryption (At-Rest)**
- Asymmetric encryption using NaCl Box (Curve25519 + Salsa20 + Poly1305)
- Public key in repository, private key in keychain or ENV vars
- Compatible with Shopify EJSON specification

**Layer 2: XOR Obfuscation (In-Binary)**
- Prevents extraction with `strings` command
- Random XOR key stored alongside obfuscated data
- Inspired by [cocoapods-keys](https://github.com/orta/cocoapods-keys)

### Implementation Details

- **Models**: `SecretConfiguration`, `EJSONFile`, `SecretError` in Sources/Xproject/Models/SecretConfig.swift
- **Services**:
  - `EJSONService` - Swift wrapper around swift-ejson library
  - `KeychainService` - macOS Keychain integration with ENV var priority
- **Utilities**: `StringObfuscator` - XOR-based obfuscation
- **Templates**: `AppKeysTemplate` - Generates obfuscated Swift code
- **Commands**: `SecretsCommand` with 4 subcommands (generate, encrypt, show, decrypt)
- **Tests**: 48 dedicated tests (12 StringObfuscator + 13 KeychainService + 13 EJSONService + 10 AppKeysTemplate)
- **Dependencies**: swift-ejson library via SPM (includes libsodium for NaCl cryptography)

### Key Features

- **Swift 6 compatibility**: Uses `@preconcurrency import EJSONKit` and `@unchecked Sendable`
- **Test serialization**: KeychainService and EJSONService tests run serialized for thread safety
- **Generated code structure**: Private byte arrays with computed property accessors
- **Prefix filtering**: Separate secrets for iOS (`ios_*`), tvOS (`tvos_*`), shared (`all_*`), services (`services_*`)
- **Type inference**: Automatic detection of String, URL, Int, Bool types
- **CamelCase naming**: `shopify_api_key` → `shopifyAPIKey`, `api_url` → `apiURL`

### Security Note

This system protects against:
- ✅ Casual `strings` extraction from binaries
- ✅ Automated secret scanning tools
- ✅ Source code leaks (EJSON encryption)
- ✅ Accidental exposure in App Store analysis

This system does NOT protect against:
- ❌ Runtime debugging (LLDB, Frida)
- ❌ Memory dumps during execution
- ❌ Determined reverse engineering

**Best Practice:** Never store critical secrets in mobile apps. Use server-side authentication with OAuth or similar protocols. This system is for protecting third-party API keys (analytics, SDKs) that must be embedded in the app.

## Provision Management

Xproject includes provisioning profile management for CI/CD with manual signing workflows. Profiles are encrypted using AES-256-CBC with PBKDF2 key derivation via the system's `/usr/bin/openssl`.

See `docs/provision-management.md` for the complete user guide with setup instructions, CI/CD integration, and troubleshooting.

### Overview

The provision management system provides:
- **AES-256-CBC encryption**: Strong encryption for profiles at rest in repositories
- **Password-based security**: PBKDF2 key derivation with 100,000 iterations
- **CI/CD support**: Environment variable priority (`PROVISION_PASSWORD` > Keychain)
- **macOS Keychain integration**: Secure password storage for local development
- **Atomic operations**: Archive management with encrypt/decrypt/install commands

### Configuration

Add to your `Xproject.yml`:

```yaml
provision:
  source_path: provision/source/          # Source directory for encryption
  archive_path: provision/profiles.zip.enc  # Encrypted archive path
  extract_path: provision/profiles/        # Extraction directory
```

### Directory Structure

```
YourProject/
├── provision/
│   ├── source/                    # Source profiles (gitignored)
│   │   ├── iOS_Dev.mobileprovision
│   │   └── iOS_Dist.mobileprovision
│   ├── profiles/                  # Extracted profiles (gitignored)
│   └── profiles.zip.enc           # Encrypted archive (committed)
└── Xproject.yml
```

### Common Workflow

```bash
# Encrypt profiles for storage
xp provision encrypt

# Decrypt and install (CI/CD)
xp provision decrypt
xp provision install

# Clean up decrypted files
xp provision cleanup
```

### Implementation Details

- **Models**: `ProvisionConfiguration`, `ProvisionProfile`, `ProvisionError` in Sources/Xproject/Models/ProvisionConfiguration.swift
- **Services**: `ProvisionService` - Handles encrypt/decrypt/install/list/cleanup operations
- **Commands**: `ProvisionCommand` with 5 subcommands (encrypt, decrypt, list, install, cleanup)
- **Tests**: ~21 dedicated tests for ProvisionService
- **Dependencies**: Uses system `/usr/bin/openssl` (no external dependencies)

### Security Note

This system protects against:
- ✅ Profile exposure in version control
- ✅ Unauthorized access to provisioning profiles

This system does NOT protect against:
- ❌ Access if password is compromised
- ❌ Installed profiles on disk (standard permissions)

## PR Report Integration

Xproject can post build warnings, errors, and test failures directly to GitHub PRs via the Checks API. This provides inline annotations on the PR diff and summary comments.

### Overview

The PR report system provides:
- **xcresult parsing**: Extracts build issues and test failures from Xcode result bundles
- **GitHub Checks API**: Posts inline annotations directly on PR diffs
- **Auto-discovery**: Automatically finds `.xcresult` bundles in the reports directory
- **Filtering**: Ignore files by glob pattern, filter warnings, collapse parallel test failures
- **Dry-run mode**: Preview what would be reported without posting

### Configuration

Add to your `Xproject.yml`:

```yaml
pr_report:
  check_name: "Xcode Build & Test"      # Optional: custom check name
  post_summary: true                     # Post summary (when false, still posts if issues)
  inline_annotations: true               # Post inline annotations
  fail_on_errors: true                   # Mark check as failed on build errors
  fail_on_test_failures: true            # Mark check as failed on test failures
  ignored_files:                         # Glob patterns to ignore
    - "Pods/**"
    - "**/Generated/**"
  ignore_warnings: false                 # Filter out warnings
  collapse_parallel_tests: true          # Deduplicate parallel test failures
```

### Available Commands

```bash
xp pr-report                           # Auto-discover and report all xcresult bundles
xp pr-report --xcresult path/to/test.xcresult  # Report specific bundle
xp pr-report --check-name "iOS Tests"  # Custom check name
xp pr-report --build-only              # Report only build warnings/errors
xp pr-report --test-only               # Report only test failures
xp pr-report --dry-run                 # Preview without posting
```

### GitHub Actions Integration

```yaml
- name: Run tests
  run: xp test --scheme MyApp

- name: Report results
  if: always()
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: xp pr-report
```

**Required environment variables** (automatically set in GitHub Actions):
- `GITHUB_TOKEN` - Authentication token with `checks:write` permission
- `GITHUB_REPOSITORY` - Repository in `owner/repo` format
- `GITHUB_SHA` - Commit SHA to annotate

### Implementation Details

- **Models**: `PRReportConfiguration`, `PRReportResult`, `PRReportError` in Sources/Xproject/Models/PRReportConfiguration.swift
- **Services**: `PRReportService` - Parses xcresult bundles, converts to annotations, reports to GitHub
- **Commands**: `PRReportCommand` with options for xcresult paths, check name, build/test modes
- **Tests**: 46 dedicated tests for PRReportService
- **Dependencies**: `swift-pr-reporter` (PRReporterKit) and `swift-xcresult-parser` (XCResultParser)

### Features

- **Glob pattern filtering**: Use patterns like `Pods/**` or `**/Generated/**` to ignore files
- **Parallel test collapsing**: Deduplicate failures from parallel test runs
- **Graceful non-PR handling**: Automatically switches to dry-run mode when not in a PR context
- **Summary generation**: Markdown summary with error/warning/test counts

### Graceful Non-PR Handling

When running outside a PR context (e.g., push to main after merge, local development), the command automatically switches to dry-run mode instead of failing:

- **Not in GitHub Actions**: Displays results without posting
- **Push event (no PR number)**: Shows results with informative skip message
- **Fork PR**: Handles read-only token gracefully

This allows the same CI workflow to run on both PR and non-PR events without conditional logic:

## Current System Overview (Reference Only)

This is a existing iOS/tvOS application build system using Ruby Rake. The project consists of a comprehensive Xcode build automation toolkit with multiple targets (iOS app, tvOS app, notification extensions, widgets) and environment-specific configuration management.

## Key Architecture Components

### Configuration System
- **Central config**: `rake-config.yml` contains app settings, Xcode build configurations, and release configurations
- **Environment management**: `env/` directory contains environment-specific YAML files with bundle identifiers, API keys, and platform-specific settings
- **Generated configs**: System automatically generates `.xcconfig` files and Swift environment files from YAML configs

### Build Pipeline
- **Multi-target support**: iOS app, tvOS app, notification extensions, widgets, TopShelf extension
- **Environment-driven builds**: Each environment (dev, staging, production, snapshot) has specific bundle IDs, signing certificates, and provisioning profiles
- **Automated versioning**: Build numbers derived from git commit count with offset, semantic versioning for marketing versions

### Secret Management
- **EJSON encryption**: API keys and secrets stored in encrypted `keys.ejson` files per environment
- **Provision profiles**: Encrypted with GPG, stored in keychain for CI/CD access
- **Keychain integration**: Automatic storage/retrieval of sensitive build credentials

## Essential Commands

### Project Setup
```bash
rake setup                    # Full project setup (bundler, brew, dependencies)
rake setup:bundler           # Install Ruby dependencies
rake setup:brew              # Install/update brew formulas
rake setup:cocoapods         # Install CocoaPods dependencies
rake setup:googlecast        # Download Google Cast SDK
```

### Environment Management
```bash
rake env:load[env_name]      # Load and configure environment (generates .xcconfig and Swift files)
rake env:current             # Show currently selected environment
```

### Building and Testing
```bash
rake xcode:tests[clean,run_danger]  # Run unit tests (clean=true for clean build, run_danger=true for CI checks)
rake xcode:release[env]             # Full release build (archive + generate IPA)
rake xcode:archive[env]             # Archive only
rake xcode:generate_ipa[env]        # Generate IPA from existing archive
rake xcode:upload[env]              # Upload to App Store Connect
```

### Version Management
```bash
rake bump:patch[target]       # Bump patch version (1.0.0 -> 1.0.1)
rake bump:minor[target]       # Bump minor version (1.0.0 -> 1.1.0)
rake bump:major[target]       # Bump major version (1.0.0 -> 2.0.0)
```

### Git Operations
```bash
rake git:commit_version_bump[target]  # Commit version changes with [skip ci]
rake git:add_tag[target]             # Tag release with version
rake git:push                        # Push branch and tags
rake git:check_dirty_repository      # Verify clean working directory
```

### Security Operations
```bash
rake ejson:encrypt           # Encrypt all environment key files
rake provision:encrypt       # Encrypt provisioning profiles
rake provision:decrypt       # Decrypt provisioning profiles
```

### Code Generation
```bash
rake swiftgen               # Generate Swift code from resources
rake swiftgen:strings       # Generate localized strings
```

## Development Workflow

1. **Environment setup**: Run `rake env:load[environment]` to configure for target environment
2. **Development**: Code changes, then `rake xcode:tests[true]` for clean test run
3. **Version bump**: Use `rake bump:patch[ios]` or appropriate version increment
4. **Release**: `rake git:commit_version_bump[ios] && rake git:add_tag[ios] && rake xcode:release[production-ios]`
5. **Deploy**: `rake xcode:upload[production-ios] && rake git:push`

## Build Targets and Environments

### Targets
- **ios**: Main iOS target
- **tvos**: tvOS target

### Release Environments
- **production-ios/tvos**: App Store releases
- **dev-ios/tvos**: Development builds
- **staging-ios/tvos**: Staging/QA builds
- **snapshot-ios/tvos**: Snapshot testing builds

## File Generation Patterns

- **`.xcconfig` files**: Generated in `*/SupportingFiles/` directories per target and configuration
- **Swift environment files**: Generated in `*/Generated/` directories using Mustache templates
- **Secret files**: Generated Swift files with encrypted keys in `*/Generated/AppKeys.swift`

## Important Dependencies

- Ruby gems: bundler, xcodeproj, git, plist, json, mustache, tty-prompt, keychain
- System tools: brew, agvtool, xcodebuild, xcpretty, ejson, gpg
- Build tools: SwiftGen, CocoaPods, Google Cast SDK

## CI/CD Integration

- **Danger integration**: Automated code review checks with multiple Dangerfiles
- **Build artifacts**: Stored in configurable `build/` and `reports/` directories
- **Environment variables**: Support for `BUNDLER_PATH`, `ARTIFACTS_PATH`, `TEST_REPORTS_PATH`, `APP_STORE_PASS`, `EJSON_PRIVATE_KEY`, `PROVISION_PASSWORD`

## Important Development Guidelines

### Architecture Decisions Made
1. **No CLI dependencies in core library**: Xproject library must remain free of ArgumentParser or other CLI frameworks
2. **Deprecated dependency managers**: Do not implement bundler, cocoapods, submodules, or carthage - these are deprecated
3. **Service-based architecture**: Business logic should be in services that CLI commands call into
4. **Swift 6.2 compliance**: Project uses Swift 6.2 with strict concurrency checking
5. **Explicit working directory**: All services and classes require explicit `workingDirectory` parameter with NO default values. Only GlobalOptions provides the default via computed property `resolvedWorkingDirectory`. This eliminates implicit `FileManager.default.currentDirectoryPath` usage throughout the codebase.
6. **Single source of truth for working directory**: CommandExecutor uses only its instance property for working directory, not method parameters. If different directory needed, create new executor instance.
7. **Temporary files directory**: All temporary files and directories MUST be created in the project's `tmp/` directory, NEVER in the system `/tmp`. The `tmp/` directory is in .gitignore and its contents can be deleted at any time, so no important files should be stored there.

### Security Guidelines
- Any use of @unchecked Sendable or nonisolated(unsafe) needs user approval

### Code Quality Guidelines
- Swift files should have less up to 300 lines

### Test Organization Guidelines
- Test directory structure must mirror source directory structure
- For example: if source file is at `Sources/Xproject/Utilities/CommandExecutor.swift`, test file should be at `Tests/XprojectTests/Utilities/CommandExecutorTests.swift`
- This ensures consistent organization and makes tests easy to locate

### Next Steps
Priority order for implementing remaining features:
1. ✅ ~~Build command~~ - **COMPLETED**: Full implementation with scheme selection, clean builds, and custom destinations
2. ✅ ~~Test command~~ - **COMPLETED**: Complete test orchestration with multi-scheme and multi-destination support
3. ✅ ~~Global --config option~~ - **COMPLETED**: Custom configuration file support across all commands
4. ✅ ~~Enhanced error handling~~ - **COMPLETED**: Informative error messages with config file context
5. ✅ ~~Dry-run functionality~~ - **COMPLETED**: Safe preview mode with executeReadOnly for discovery operations
6. ✅ ~~Release command~~ - **COMPLETED**: Archive, IPA generation, and App Store upload with automatic/manual signing (139 tests passing)

7. ✅ ~~Environment management~~ - **COMPLETED**: Full environment system with xcconfig generation, Swift code generation, variable mapping, validation (226 tests passing)
8. ✅ ~~Version management~~ - **COMPLETED**: Auto-increment build numbers, semantic versioning, git tagging (56 tests passing)
9. ✅ ~~Git operations~~ - **COMPLETED**: Commit, tag, and push automation with safety checks
10. ✅ ~~Secret management~~ - **COMPLETED**: Dual-layer security with EJSON encryption and XOR obfuscation
11. ✅ ~~Provision management~~ - **COMPLETED**: Encrypted profile storage and CI/CD installation
12. ✅ ~~PR Report integration~~ - **COMPLETED**: Post build/test results to GitHub PRs via Checks API (392 total tests passing)

**Remaining Work:**
- None for core functionality - all planned features complete!

### Future Enhancements
- Support for additional configuration formats (TOML, Swift configs)
- Plugin-based architecture for extensibility
- SwiftGen integration for code generation

## Documentation

The `docs/` directory contains user guides and reference documentation:

- `environment-setup.md` - Detailed setup guide for the environment management system
- `secrets-management.md` - Complete user guide for secret management with EJSON encryption
- `swift-testing_api.md` - Swift Testing framework API reference
- `swift-testing-playbook.md` - Best practices and patterns for Swift Testing
