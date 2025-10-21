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
- `EnvironmentService`: Manages environment configurations, xcconfig generation, and variable mapping

**Key Utilities:**
- `OutputFormatter`: Consistent formatting for CLI output with info blocks and structured display
- `CommandExecutor`: Utility for executing shell commands safely with dry-run support and executeReadOnly for discovery operations
- `NestedDictionary`: Dot notation access for nested YAML structures (e.g., "apps.ios.bundle_identifier")

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
xp env list        # List available environments
xp env show        # Show environment variables (current or specific)
xp env current     # Show currently activated environment
xp env load    # Load an environment and generate xcconfig files
xp env validate    # Validate environment configuration

# Examples
xp -C /path/to/project config show
xp --working-directory MyProject build --scheme MyApp --clean
xp test --config my-config.yml --scheme MyApp --clean --dry-run
xp release production-ios
xp release dev-ios --archive-only --dry-run
xp setup --dry-run
xp config --config custom.yml validate
xp env list
xp env load dev --dry-run
xp env load production
xp env show dev
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
└── Xproject.yml                # Enable with environment.enabled: true
```

### Quick Start

1. **Enable in Xproject.yml:**
   ```yaml
   environment:
     enabled: true
   ```

2. **Create env/config.yml:**
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

3. **Create environment files (e.g., env/dev/env.yml):**
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

4. **Activate environment:**
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
  enabled: true
  outputs:
    # Base class - automatically includes ALL root-level variables
    - path: MyApp/Generated/EnvironmentService.swift
      prefixes: []  # Empty - base type auto-includes root-level
      type: base
    # Extension - explicitly specify namespaces
    - path: MyApp/Generated/EnvironmentService+App.swift
      prefixes: [apps, features]
      type: extension
```

Features:
- **Base type auto-includes root-level**: Base class automatically includes all root-level variables
- **Namespace filtering**: Extensions filter by namespace (e.g., `apps`, `features`)
- **CamelCase conversion**: `bundle_identifier` → `bundleIdentifier`, `api_url` → `apiURL`
- **Type inference**: Automatic URL, String, Int, Bool detection
- **Base class or extension**: Generate standalone class or extend existing
- **URL handling**: Auto-detect URL properties by name suffix (`*URL`, `*Url`)

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

## Current System Overview (Reference Only)

This is the existing Nebula iOS/tvOS application build system using Ruby Rake. The project consists of a comprehensive Xcode build automation toolkit with multiple targets (iOS app, tvOS app, notification extensions, widgets) and environment-specific configuration management.

## Key Architecture Components

### Configuration System
- **Central config**: `rake-config.yml` contains app settings, Xcode build configurations, and release configurations
- **Environment management**: `env/` directory contains environment-specific YAML files with bundle identifiers, API keys, and platform-specific settings
- **Generated configs**: System automatically generates `.xcconfig` files and Swift environment files from YAML configs

### Build Pipeline
- **Multi-target support**: iOS (Nebula), tvOS (NebulaTV), notification extensions, widgets, TopShelf extension
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
- **ios**: Main iOS target in `Nebula.xcodeproj`
- **tvos**: tvOS target in `TV/TV.xcodeproj`

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

**Remaining Work:**
1. Version management - Auto-increment build numbers, semantic versioning, git tagging
2. Git operations - Commit, tag, and push automation

### Future Enhancements
- Add Danger integration support for test command (--run-danger flag)
- Implement pre-test, build, test, and post-test Danger phases
- Support for additional configuration formats (TOML, Swift configs)
- Plugin-based architecture for extensibility
