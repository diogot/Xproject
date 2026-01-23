# Xproject

A modern Swift command line tool for Xcode project build automation.

## Installation & Usage

**No external dependencies required!** Xproject runs with just Xcode's built-in Swift tooling.

### Requirements
- **Swift 6.2+** (included with Xcode 16.4+)
- **macOS 15+** (specified in Package.swift platforms)

### Quick Start

1. **Install from GitHub Releases (recommended):**
   ```bash
   curl -L https://github.com/diogot/xp/releases/latest/download/xp-macos-universal.tar.gz | tar xz
   sudo mv xp /usr/local/bin/
   xp --version
   ```

   Or build from source:
   ```bash
   git clone https://github.com/diogot/xp.git
   cd xp/Xproject
   swift build -c release
   sudo cp .build/release/xp /usr/local/bin/
   ```

2. **Create `Xproject.yml` in your project root:**

   This is the only required configuration file. Create it with:

   ```yaml
   # Minimal configuration (required)
   app_name: MyApp
   project_path:
     ios: MyApp.xcodeproj

   # Test configuration (for xp test)
   xcode:
     tests:
       schemes:
         - scheme: MyApp
           build_destination: "generic/platform=iOS Simulator"
           test_destinations:
             - platform=iOS Simulator,name=iPhone 16 Pro
   ```

   **Required fields:**
   - `app_name` - Your app's name
   - `project_path` - Map of target names to `.xcodeproj` paths

   **Optional features** (add as needed):
   ```yaml
   # Homebrew dependencies
   setup:
     brew:
       formulas:
         - swiftlint

   # Release builds
   xcode:
     release:
       production-ios:
         scheme: MyApp
         configuration: Release
         destination: iOS
   ```

   **See also:**
   - [Configuration Reference](docs/configuration-reference.md) - Complete list of all options
   - [Environment Setup](docs/environment-setup.md) - xcconfig and Swift code generation
   - [Secrets Management](docs/secrets-management.md) - EJSON encryption
   - [Provision Management](docs/provision-management.md) - Provisioning profiles for CI/CD

3. **Run commands:**
   ```bash
   # Show help
   xp --help

   # Setup project
   xp setup

   # Build project for testing
   xp build --scheme MyApp --clean

   # Run tests
   xp test --scheme MyApp --clean

   # Create release
   xp release production-ios
   ```

### Available Commands

- `xp setup` - Setup project dependencies and environment
- `xp build` - Build the Xcode project for testing
- `xp test` - Run unit tests with multi-destination support
- `xp release` - Create release builds with archive, IPA generation, and App Store upload
- `xp clean` - Remove build artifacts and test reports directories
- `xp config` - Manage and validate project configuration
- `xp env` - Manage environment configurations (dev, staging, production)
- `xp secrets` - Manage encrypted secrets with EJSON and XOR obfuscation
- `xp version` - Manage semantic versioning and build numbers
- `xp provision` - Manage encrypted provisioning profiles for CI/CD
- `xp pr-report` - Post build/test results to GitHub PRs via Checks API

### Global Options

All commands support the following global options:
- `-C, --working-directory <path>` - Working directory for the command (default: current directory)
- `-c, --config <path>` - Specify custom configuration file (default: auto-discover Xproject.yml, rake-config.yml)
- `-v, --verbose` - Show detailed output and commands being executed
- `--dry-run` - Show what would be done without executing (available on most commands)

### Command Examples

```bash
# Run from any directory with -C flag
xp -C /path/to/project config show
xp --working-directory MyProject build

# Use custom configuration file
xp test --config my-project.yml --dry-run

# Run tests with specific options
xp test --scheme MyApp --clean --destination "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro"

# Setup with dry-run preview
xp setup --dry-run

# Clean build artifacts
xp clean --dry-run

# Validate configuration
xp config validate

# Show current configuration with verbose output
xp config show --verbose

# Create release builds
xp release production-ios
xp release dev-ios --archive-only
xp release staging-ios --skip-upload --dry-run

# Environment management
xp env list
xp env load dev --dry-run
xp env load production
xp env show dev

# Secret management
xp secrets generate-keys dev
xp secrets generate dev
xp secrets encrypt
xp secrets show dev
xp secrets decrypt dev  # Dev only

# Version management
xp version show
xp version bump patch
xp version commit
xp version tag --environment production
xp version push

# PR reporting (GitHub Actions)
xp pr-report                          # Auto-discover xcresult bundles
xp pr-report --check-name "iOS Tests" # Custom check name
xp pr-report --dry-run                # Preview without posting
```

## Environment Management

Xproject includes a powerful environment management system for handling multiple deployment environments (dev, staging, production, etc.) with automatic `.xcconfig` file generation.

### Quick Setup

1. **Create environment configuration (`env/config.yml`):**
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

3. **Create environment files:**
   ```yaml
   # env/dev/env.yml
   environment_name: development
   api_url: https://dev-api.example.com

   apps:
     bundle_identifier: com.example.myapp.dev
     display_name: MyApp Dev
     ios:
       app_icon_name: AppIcon
       provision_profile: Development
   ```

4. **Create output directory and activate:**
   ```bash
   mkdir -p MyApp/Config
   xp env load dev
   ```

### Features

- **Configuration-driven**: Define targets and variable mappings in YAML, no hardcoded paths
- **Nested YAML structure**: Access values with dot notation (`apps.ios.bundle_identifier`)
- **Bundle ID suffixes**: Automatic suffix appending for app extensions (`.widget`, `.notification-content`)
- **Per-configuration overrides**: Different variables for debug vs release builds
- **Multiple targets**: Support for main app + extensions (widgets, notification extensions, etc.)
- **Swift code generation**: Type-safe Swift files with namespace filtering, camelCase conversion, and automatic type inference
- **Validation**: Comprehensive validation of configuration and environment files
- **Dry-run mode**: Preview xcconfig and Swift generation without writing files

### Available Commands

```bash
xp env list                    # List available environments
xp env show [name]             # Display environment variables
xp env current                 # Show currently activated environment
xp env load <name>         # Activate environment and generate xcconfigs
xp env validate                # Validate environment configuration
```

### Generated Files

When you activate an environment, Xproject generates `.xcconfig` files for each target and configuration:

```
MyApp/Config/
├── MyApp.debug.xcconfig       # Debug configuration
└── MyApp.release.xcconfig     # Release configuration
```

These files contain your environment-specific variables:
```
// Generated by xp env load dev
// Target: MyApp
// Configuration: release
API_URL = https://dev-api.example.com
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
BUNDLE_DISPLAY_NAME = MyApp Dev
PRODUCT_BUNDLE_IDENTIFIER = com.example.myapp.dev
PROVISIONING_PROFILE_SPECIFIER = Development
```

### Xcode Integration

1. In Xcode, select your project → target → Info tab
2. Under Configurations, set:
   - Debug → `MyApp.debug.xcconfig`
   - Release → `MyApp.release.xcconfig`

Build settings from xcconfig files will override project settings.

### Swift Code Generation (Optional)

Automatically generate type-safe Swift files from environment variables:

```yaml
# Add to env/config.yml
swift_generation:
  outputs:
    # Base class - automatically includes ALL root-level variables
    - path: MyApp/Generated/EnvironmentService.swift
      prefixes: []
      type: base
    # Extension - specify namespaces to include
    - path: MyApp/Generated/EnvironmentService+App.swift
      prefixes: [apps, features]
      type: extension
```

Generated Swift code:
```swift
public final class EnvironmentService {
    public init() {}
    public let apiURL = url("https://dev-api.example.com")
    public let environmentName = "development"
}

extension EnvironmentService {
    public var bundleIdentifier: String { "com.example.myapp.dev" }
    public var debugMenu: Bool { true }
}
```

### .gitignore Recommendations

Add these to your `.gitignore`:
```gitignore
# Environment management
env/.current
**/Config/*.xcconfig
**/Generated/EnvironmentService*.swift  # If using Swift generation
```

**Documentation**: See `docs/environment-setup.md` for detailed setup guide and advanced features.

## Secret Management

Xproject includes a **dual-layer security system** for managing API keys and secrets:
- **Layer 1: EJSON encryption** (at-rest) - Secrets encrypted in repository using asymmetric cryptography
- **Layer 2: XOR obfuscation** (in-binary) - Prevents extraction from compiled app with `strings` command

### Quick Start

1. **Configure in your Xproject.yml:**
   ```yaml
   secrets:
     swift_generation:
       outputs:
         - path: MyApp/Generated/AppKeys.swift
           prefixes: [all, ios]
   ```

2. **Create encrypted secrets file (`env/dev/keys.ejson`):**
   ```json
   {
     "_public_key": "a1b2c3d4...",
     "shopify_api_key": "EJ[1:...]",
     "mux_key": "EJ[1:...]"
   }
   ```

3. **Generate obfuscated Swift code:**
   ```bash
   xp env load dev  # Automatically generates AppKeys.swift
   # or manually:
   xp secrets generate dev
   ```

### Features

- **Dual-layer protection**: EJSON (repo) + XOR obfuscation (binary)
- **No plaintext in binaries**: Defeats `strings` command extraction
- **macOS Keychain integration**: Secure private key storage
- **ENV var support**: `EJSON_PRIVATE_KEY` for CI/CD
- **Smart Swift generation**: CamelCase conversion, URL/API suffix handling
- **Type-safe code**: Automatic type inference (String, URL, Int, Bool)

### Generated Code Example

```swift
// ✅ Secure - Obfuscated byte arrays
final class AppKeys {
    private static let _shopifyApiKey: [UInt8] = [135, 89, 20, 175, ...]

    static var shopifyApiKey: String {
        String(bytes: _shopifyApiKey.deobfuscated, encoding: .utf8)!
    }
}
```

### Available Commands

```bash
xp secrets generate <env>     # Generate obfuscated AppKeys.swift
xp secrets encrypt [env]       # Encrypt EJSON files
xp secrets show <env>          # Display file info
xp secrets decrypt <env>       # Decrypt and display (dev only)
```

### .gitignore Recommendations

```gitignore
# Secret management
**/Generated/AppKeys*.swift
env/*/.ejson_keypair
env/*/keys.json
```

**Security Note:** This protects against casual inspection and automated scanning, but not against determined reverse engineering. Never store critical secrets in mobile apps - use server-side authentication.

## PR Report Integration

Post build warnings, errors, and test failures directly to GitHub PRs via the Checks API.

### Quick Setup

1. **Configure in your Xproject.yml:**
   ```yaml
   pr_report:
     check_name: "Xcode Build & Test"
     ignored_files:
       - "Pods/**"
       - "**/Generated/**"
   ```

2. **Add to your GitHub Actions workflow:**
   ```yaml
   - name: Run tests
     run: xp test --scheme MyApp

   - name: Report results
     if: always()
     env:
       GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
     run: xp pr-report
   ```

### Features

- **Auto-discovery**: Finds all `.xcresult` bundles in the reports directory
- **Inline annotations**: Posts warnings/errors directly on PR diff lines
- **Summary comments**: Generates markdown summary with counts
- **Filtering**: Ignore files by glob pattern, filter warnings
- **Parallel test collapsing**: Deduplicates failures from parallel test runs
- **Dry-run mode**: Preview what would be reported

### Available Commands

```bash
xp pr-report                           # Auto-discover and report
xp pr-report --xcresult path/to/test.xcresult
xp pr-report --check-name "iOS Tests"
xp pr-report --build-only              # Only build warnings/errors
xp pr-report --test-only               # Only test failures
xp pr-report --dry-run                 # Preview without posting
```

## Development

```bash
# Run tests
swift test

# Build
swift build

# Run in development
swift run xp --help
```

## Dependencies

Xproject uses Swift Package Manager (SPM) for dependency management. All dependencies are automatically resolved during build.

### External Dependencies
- **Yams** - YAML parsing for configuration files
- **swift-ejson** (EJSONKit) - EJSON encryption/decryption for secret management
  - Includes libsodium (NaCl cryptography) via precompiled xcframework
- **swift-pr-reporter** (PRReporterKit) - GitHub Checks API integration for PR reporting
- **swift-xcresult-parser** (XCResultParser) - Xcode xcresult bundle parsing
- **ArgumentParser** - CLI argument parsing

### System Requirements
- **Swift 6.2+** (included with Xcode 16.4+)
- **macOS 15+**
- **Xcode Command Line Tools** (for `xcodebuild`, `agvtool`, `git`)

**No additional installation required** - all dependencies managed via SPM.

## Features

### ✅ Completed
- **Working directory support** - Run commands from any directory with `-C/--working-directory`
- **Multi-scheme and multi-destination testing** - Run tests across multiple iOS simulators
- **Custom configuration files** - Use `--config` option to specify project-specific configs
- **Dry-run mode** - Preview operations without executing them (`--dry-run`)
- **Verbose mode** - Show detailed command output with `--verbose`
- **Enhanced error handling** - Clear error messages with config file context
- **Legacy compatibility** - Works with existing rake-config.yml files
- **Type-safe configuration** - Swift Codable structs with validation
- **Homebrew integration** - Automated tool installation and updates
- **Clean architecture** - Separated CLI and business logic with explicit working directory handling
- **Improved CLI output** - Clear info blocks with working directory and configuration display, structured environment variable formatting
- **Release command** - Archive creation, IPA generation, and App Store upload with automatic/manual signing support
- **Environment management** - Complete environment system with xcconfig generation, variable mapping, and multi-environment support
- **Swift code generation** - Type-safe Swift code from environment variables with namespace filtering, camelCase conversion, and automatic type inference (String, URL, Int, Bool)
- **Version management** - Automated version bumping (patch/minor/major), build numbers from git commits, and git tagging
- **Git operations** - Automated version commit, tag creation with environment support, and push to remote
- **Secret management** - Dual-layer security (EJSON + XOR obfuscation) for API keys with binary protection against `strings` extraction
- **Provision management** - Encrypted provisioning profile storage and installation for CI/CD workflows
- **PR Report integration** - Post build warnings, errors, and test failures to GitHub PRs via Checks API with inline annotations

### 🚧 Future Enhancements
- **Code generation** - SwiftGen integration for resources
