# Configuration Reference

This document provides a complete reference for the `Xproject.yml` configuration file.

## Quick Links

- [Minimal Configuration](#minimal-configuration)
- [Complete Configuration](#complete-configuration)
- [Configuration Sections](#configuration-sections)
  - [Root Fields](#root-fields)
  - [setup](#setup)
  - [xcode](#xcode)
  - [environment](#environment)
  - [version](#version)
  - [secrets](#secrets)
  - [provision](#provision)
  - [pr_report](#pr_report)

## Minimal Configuration

The simplest valid configuration requires only two fields:

```yaml
app_name: MyApp
project_path:
  ios: MyApp.xcodeproj
```

## Complete Configuration

Below is a complete example with all available options:

```yaml
# =============================================================================
# REQUIRED FIELDS
# =============================================================================

# Your app's name (used for display and keychain services)
app_name: MyApp

# Map of target names to .xcodeproj paths
# Use "ios", "tvos", etc. as keys - these are used by version and release commands
project_path:
  ios: MyApp.xcodeproj
  tvos: TV/TV.xcodeproj

# Optional: Use workspace instead of project for builds
# workspace_path: MyApp.xcworkspace

# =============================================================================
# SETUP - Homebrew dependencies (xp setup)
# =============================================================================

setup:
  brew:
    enabled: true                    # Optional, defaults to true
    formulas:
      - swiftlint
      - swiftformat

# =============================================================================
# XCODE - Build, test, and release configuration
# =============================================================================

xcode:
  version: "16.4"                    # Required: Xcode version for display
  build_path: build                  # Optional: Build artifacts directory (default: build)
  reports_path: reports              # Optional: Test reports directory (default: reports)

  # Test configuration (xp test)
  tests:
    schemes:
      - scheme: MyApp
        build_destination: "generic/platform=iOS Simulator"
        test_destinations:
          - platform=iOS Simulator,name=iPhone 16 Pro
          - platform=iOS Simulator,name=iPad Pro (13-inch) (M4)

      - scheme: MyAppTV
        build_destination: "generic/platform=tvOS Simulator"
        test_destinations:
          - platform=tvOS Simulator,name=Apple TV 4K (3rd generation)

  # Release configuration (xp release)
  release:
    # Development iOS build
    dev-ios:
      scheme: MyApp
      configuration: Release         # Optional: Xcode build configuration
      output: MyApp-Dev              # Output filename (without extension)
      destination: iOS               # Platform: iOS or tvOS
      type: ios                      # Archive type: ios or appletvos
      app_store_account: dev@example.com  # Optional: App Store Connect account
      sign:
        signingStyle: automatic      # automatic or manual
        teamID: ABCD1234EF           # Apple Developer Team ID

    # Production iOS build with manual signing
    production-ios:
      scheme: MyApp
      configuration: Release
      output: MyApp
      destination: iOS
      type: ios
      app_store_account: release@example.com
      sign:
        signingStyle: manual
        teamID: ABCD1234EF
        signingCertificate: "iPhone Distribution"
        provisioningProfiles:
          com.example.myapp: "MyApp Distribution"
          com.example.myapp.widget: "MyApp Widget Distribution"

    # tvOS build
    production-tvos:
      scheme: MyAppTV
      configuration: Release
      output: MyAppTV
      destination: tvOS
      type: appletvos
      sign:
        signingStyle: automatic
        teamID: ABCD1234EF

# =============================================================================
# ENVIRONMENT - xcconfig and Swift code generation (xp env)
# =============================================================================

# Enable environment management
# Requires env/config.yml - see docs/environment-setup.md
environment:
  enabled: true

# =============================================================================
# VERSION - Semantic versioning and git tags (xp version)
# =============================================================================

version:
  build_number_offset: 0             # Offset added to git commit count
  tag_format: "{env}-{target}/{version}-{build}"  # Optional custom format

# =============================================================================
# SECRETS - EJSON encryption and Swift code generation (xp secrets)
# =============================================================================

# Enable secret management
# Requires env/<environment>/keys.ejson - see docs/secrets-management.md
secrets:
  enabled: true
  swift_generation:
    outputs:
      # Generate AppKeys.swift with secrets filtered by prefix
      - path: MyApp/Generated/AppKeys.swift
        prefixes: [all, ios]         # Include all_* and ios_* secrets

      - path: TV/Generated/AppKeys.swift
        prefixes: [all, tvos]        # Include all_* and tvos_* secrets

# =============================================================================
# PROVISION - Encrypted provisioning profiles (xp provision)
# =============================================================================

# Enable provisioning profile management
# See docs/provision-management.md
provision:
  enabled: true
  source_path: provision/source/     # Source profiles for encryption
  archive_path: provision/profiles.zip.enc  # Encrypted archive
  extract_path: provision/profiles/  # Extraction directory

# =============================================================================
# PR_REPORT - GitHub PR integration (xp pr-report)
# =============================================================================

pr_report:
  enabled: true
  check_name: "Xcode Build & Test"   # Optional: GitHub Check Run name
  post_summary: true                 # Post summary comment
  inline_annotations: true           # Post inline annotations on diff
  fail_on_errors: true               # Fail check if build errors exist
  fail_on_test_failures: true        # Fail check if tests fail
  ignore_warnings: false             # Filter out warnings from report
  collapse_parallel_tests: true      # Deduplicate parallel test failures
  ignored_files:                     # Glob patterns to ignore
    - "Pods/**"
    - "**/Generated/**"
    - "vendor/**"
```

## Configuration Sections

### Root Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `app_name` | String | Yes | Your app's name |
| `project_path` | Map | Yes | Target name to `.xcodeproj` path mapping |
| `workspace_path` | String | No | Path to `.xcworkspace` (overrides project_path for builds) |

### setup

Homebrew dependencies installed by `xp setup`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `brew.enabled` | Bool | `true` | Enable Homebrew installation |
| `brew.formulas` | [String] | `[]` | List of formulas to install |

### xcode

Build, test, and release configuration.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | String | Required | Xcode version (for display) |
| `build_path` | String | `build` | Build artifacts directory |
| `reports_path` | String | `reports` | Test reports directory |
| `tests` | Object | - | Test configuration |
| `release` | Map | - | Release configurations by environment name |

#### tests.schemes[]

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scheme` | String | Yes | Xcode scheme name |
| `build_destination` | String | Yes | Destination for building (e.g., `generic/platform=iOS Simulator`) |
| `test_destinations` | [String] | Yes | Destinations for running tests |

#### release.\<name\>

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scheme` | String | Yes | Xcode scheme name |
| `configuration` | String | No | Xcode build configuration |
| `output` | String | Yes | Output filename (without extension) |
| `destination` | String | Yes | Platform: `iOS` or `tvOS` |
| `type` | String | Yes | Archive type: `ios` or `appletvos` |
| `app_store_account` | String | No | App Store Connect account email |
| `sign` | Object | No | Code signing configuration |

#### release.\<name\>.sign

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `signingStyle` | String | No | `automatic` or `manual` |
| `teamID` | String | No | Apple Developer Team ID |
| `signingCertificate` | String | Manual only | Certificate name (e.g., `iPhone Distribution`) |
| `provisioningProfiles` | Map | Manual only | Bundle ID to profile name mapping |

### environment

Enables environment management with xcconfig generation.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `enabled` | Bool | Yes | Enable environment management |

When enabled, requires `env/config.yml`. See [Environment Setup Guide](environment-setup.md).

### version

Version management configuration.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `build_number_offset` | Int | `0` | Offset added to git commit count for build number |
| `tag_format` | String | `{env}-{target}/{version}-{build}` | Custom tag format |

### secrets

Secret management with EJSON encryption.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `enabled` | Bool | Yes | Enable secret management |
| `swift_generation.outputs` | [Object] | No | Swift code generation outputs |

#### secrets.swift_generation.outputs[]

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | String | Yes | Output Swift file path |
| `prefixes` | [String] | Yes | Secret prefixes to include (e.g., `[all, ios]`) |

When enabled, requires `env/<environment>/keys.ejson`. See [Secrets Management Guide](secrets-management.md).

### provision

Provisioning profile management.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | Bool | Required | Enable provision management |
| `source_path` | String | `provision/source/` | Directory with source profiles |
| `archive_path` | String | `provision/profiles.zip.enc` | Encrypted archive path |
| `extract_path` | String | `provision/profiles/` | Extraction directory |

See [Provision Management Guide](provision-management.md).

### pr_report

GitHub PR reporting via Checks API.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | Bool | Required | Enable PR reporting |
| `check_name` | String | `Xcode Build & Test` | GitHub Check Run name |
| `post_summary` | Bool | `true` | Post summary comment |
| `inline_annotations` | Bool | `true` | Post inline annotations |
| `fail_on_errors` | Bool | `true` | Fail if build errors exist |
| `fail_on_test_failures` | Bool | `true` | Fail if tests fail |
| `ignore_warnings` | Bool | `false` | Filter out warnings |
| `collapse_parallel_tests` | Bool | `true` | Deduplicate parallel failures |
| `ignored_files` | [String] | `[]` | Glob patterns to ignore |

## Related Documentation

- [Environment Setup Guide](environment-setup.md) - Detailed environment and xcconfig setup
- [Secrets Management Guide](secrets-management.md) - EJSON encryption and obfuscation
- [Provision Management Guide](provision-management.md) - Provisioning profile encryption
