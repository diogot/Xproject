# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Intent

This repository is undergoing a migration from Ruby Rake to a modern Swift command line tool called **XProject**. The existing Ruby rakelib serves as a reference implementation that we are incrementally migrating to Swift, taking the opportunity to:

- **Modernize configuration**: Move from YAML to more flexible formats (TOML, Swift configs)
- **Improve type safety**: Leverage Swift's type system for compile-time validation
- **Enhance extensibility**: Design a plugin-based architecture for easy feature additions
- **Better developer experience**: Create more intuitive commands and helpful error messages
- **Reduce dependencies**: Eliminate Ruby/gem dependencies for easier CI/CD setup

**Important**: The current Ruby rakelib should be used only as reference for understanding existing functionality. All new development should focus on the Swift XProject tool, migrating features one by one while improving upon the original design.

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

## Security Guidelines

- Any use of @unchecked Sendable or nonisolated(unsafe) needs my approval