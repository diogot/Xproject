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
- ✅ **Global --config option**: Custom configuration file support across all commands
- ✅ **Enhanced error handling**: Informative error messages with config file context
- ✅ **Dry-run functionality**: Safe preview mode for all commands with executeReadOnly for discovery operations
- ✅ **Command execution utilities**: Safe shell command execution with proper error handling
- ✅ **Clean architecture**: Separated CLI concerns from business logic

### Architecture Overview
**Targets:**
- `XprojectCLI`: CLI layer using ArgumentParser, calls into Xproject library
- `Xproject`: Core business logic library (configuration, services, utilities) - no CLI dependencies
- `XprojectTests`: Test suite for core library

**Key Services:**
- `ConfigurationService`: Thread-safe singleton for loading and caching YAML configs with custom config file support
- `SetupService`: Handles project setup (currently Homebrew only)
- `BuildService`: Handles building for tests, archiving, IPA generation, and uploads with Xcode discovery
- `TestService`: Orchestrates test workflows including build and test phases across multiple schemes/destinations
- `CommandExecutor`: Utility for executing shell commands safely with dry-run support and executeReadOnly for discovery operations

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
--config <path>    # Specify custom configuration file (auto-discovers Xproject.yml, rake-config.yml by default)
--dry-run          # Show what would be done without executing (available on most commands)

# Core commands
xp setup           # Install/update Homebrew formulas from config
xp config show     # Display current configuration
xp config validate # Validate configuration files with comprehensive checks
xp build           # Build for testing (supports --scheme, --clean, --destination)
xp test            # Run tests (supports --scheme, --clean, --skip-build, --destination)
xp release         # TODO: Implement release functionality

# Examples
xp test --config my-config.yml --scheme MyApp --clean --dry-run
xp setup --dry-run
xp config --config custom.yml validate
```

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
4. **Swift 6.1 compliance**: Project uses Swift 6.1 with strict concurrency checking

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

**Remaining Work:**
1. Release command (migrate from xcode.rake) - Archive, IPA generation, and App Store upload
2. Environment management features - Support for different deployment environments

### Future Enhancements
- Add Danger integration support for test command (--run-danger flag)
- Implement pre-test, build, test, and post-test Danger phases
- Support for additional configuration formats (TOML, Swift configs)
- Plugin-based architecture for extensibility
