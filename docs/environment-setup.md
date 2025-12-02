# Environment Management Setup Guide

This guide explains how to set up and use the environment management system in Xproject.

## Overview

The environment management system allows you to:
- Define multiple environments (dev, staging, production, etc.)
- Generate environment-specific `.xcconfig` files
- Manage configuration variables using YAML
- Support multiple targets with bundle ID suffixes

## Directory Structure

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

## Setup Steps

### 1. Create env/config.yml

Define your targets and variable mappings:

```yaml
targets:
  - name: MyApp
    xcconfig_path: MyApp/Config        # Where to generate xcconfigs
    shared_variables:
      PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_identifier
      BUNDLE_DISPLAY_NAME: apps.display_name
      ASSETCATALOG_COMPILER_APPICON_NAME: apps.ios.app_icon_name
      API_URL: api_url
    configurations:
      debug:
      release:
        variables:
          PROVISIONING_PROFILE_SPECIFIER: apps.ios.provision_profile
```

### 3. Create Environment Files

Create `env/dev/env.yml`:

```yaml
# Development Environment
environment_name: development
api_url: https://dev-api.example.com

apps:
  bundle_identifier: com.example.myapp.dev
  display_name: MyApp Dev
  ios:
    app_icon_name: AppIcon
    provision_profile: Development
```

Create `env/production/env.yml`:

```yaml
# Production Environment
environment_name: production
api_url: https://api.example.com

apps:
  bundle_identifier: com.example.myapp
  display_name: MyApp
  ios:
    app_icon_name: AppIcon
    provision_profile: AppStore Distribution
```

### 4. Create Config Directory

```bash
mkdir -p MyApp/Config
```

### 5. Update .gitignore

Add these lines to your `.gitignore`:

```gitignore
# Environment management
env/.current
**/Config/*.xcconfig
```

## Usage

### List Available Environments

```bash
xp env list
```

Output:
```
Available environments:
  dev
  production
* staging

Current: staging
```

### Show Environment Variables

```bash
# Show current environment
xp env show

# Show specific environment
xp env show dev
```

### Activate an Environment

```bash
# Preview changes (dry-run)
xp env load dev --dry-run

# Actually activate
xp env load dev
```

This will:
1. Load variables from `env/dev/env.yml`
2. Generate `.xcconfig` files in `MyApp/Config/`
3. Update `env/.current` to track the active environment

### Check Current Environment

```bash
xp env current
```

### Validate Configuration

```bash
xp env validate
```

This checks:
- `env/config.yml` syntax and structure
- All environment `env.yml` files are valid
- All required variables are present
- xcconfig output directories exist

## Swift Code Generation

The environment system can automatically generate type-safe Swift code from your environment variables.

### Enable Swift Generation

Add to your `env/config.yml`:

```yaml
swift_generation:
  outputs:
    # Base class - automatically includes ALL root-level variables
    - path: MyApp/Generated/EnvironmentService.swift
      prefixes: []  # Empty - base type auto-includes root-level variables
      type: base
    # Extension with namespace variables
    - path: MyApp/Generated/EnvironmentService+App.swift
      prefixes: [apps, features]
      type: extension
    # Extension in a different module that needs to import the base class module
    - path: MyAppKit/Generated/EnvironmentService+Kit.swift
      prefixes: [services]
      type: extension
      imports: [MyApp]  # Import module containing the base EnvironmentService class
```

### Output Types

- **base**: Creates a standalone `EnvironmentService` class with `let` properties
  - **Automatically includes ALL root-level variables** (no prefixes needed)
  - Can optionally add namespaces to include in the base class
- **extension**: Creates an extension with computed `var` properties
  - **Requires explicit prefixes** to specify which namespaces to include

### Cross-Module Imports

When base and extension are in **different modules**, the extension file needs to import the module containing the base class. Use the `imports` option:

```yaml
swift_generation:
  outputs:
    - path: ModuleA/Generated/EnvironmentService.swift
      type: base
    - path: ModuleB/Generated/EnvironmentService+Feature.swift
      type: extension
      prefixes: [features]
      imports: [ModuleA]  # Extension imports base class module
```

Generated output for the extension:

```swift
import Foundation
import ModuleA

extension EnvironmentService {
    public var featureEnabled: Bool { true }
}
```

**Note**: Module names are validated to prevent code injection. Only valid Swift identifiers matching `^[A-Za-z_][A-Za-z0-9_]*$` are accepted. Invalid names are skipped with a warning.

### Namespace Filtering

Variables are filtered by **namespace** and converted to camelCase:

**Base type behavior**:
- **Automatically includes ALL root-level variables** (no prefix needed)
- Root-level variables: `environment_name`, `api_url`, `app_url_scheme`, etc.

**Extension type behavior**:
- **Requires explicit prefixes** to specify namespaces
- Namespaces include all nested variables

**Examples**:

| YAML Structure | Output Type | Prefix | Generated Property |
|----------------|-------------|--------|-------------------|
| Root: `environment_name` | `base` | *(auto)* | `environmentName` |
| Root: `api_url` | `base` | *(auto)* | `apiURL` (URL type) |
| `apps.bundle_identifier` | `extension` | `apps` | `bundleIdentifier` |
| `apps.ios.app_icon_name` | `extension` | `apps` | `iosAppIconName` |
| `features.debug_menu` | `extension` | `features` | `debugMenu` |

### Type Inference

Types are automatically inferred from values:

- **URL**: Auto-detected when property name ends with `URL` or `Url`
- **String**: Default for text values
- **Int**: Whole numbers
- **Bool**: `true`/`false` values

### Example Generated Code

Given this environment file:
```yaml
environment_name: development
api_url: https://dev-api.example.com

apps:
  bundle_identifier: com.example.app.dev
  display_name: MyApp Dev

features:
  debug_menu: true
  analytics: false
```

**Generated EnvironmentService.swift**:
```swift
//
// EnvironmentService.swift
// Generated by xp env load dev
// DO NOT EDIT - This file is auto-generated
//

import Foundation

public final class EnvironmentService {
    public init() {}

    public let apiURL = url("https://dev-api.example.com")
    public let appURLScheme = "myapp-dev"
    public let environmentName = "development"
}

private func url(_ urlString: String) -> URL {
    // swiftlint:disable:next force_unwrapping
    return URL(string: urlString)!
}
```

**Generated EnvironmentService+App.swift**:
```swift
//
// EnvironmentService+Extension.swift
// Generated by xp env load dev
// DO NOT EDIT - This file is auto-generated
//

import Foundation

extension EnvironmentService {
    public var analytics: Bool { false }
    public var bundleIdentifier: String { "com.example.app.dev" }
    public var debugMenu: Bool { true }
    public var displayName: String { "MyApp Dev" }
}
```

### Using Generated Code

```swift
let env = EnvironmentService()
print(env.environmentName)   // "development"
print(env.apiURL)            // URL
print(env.appURLScheme)      // "myapp-dev"
print(env.bundleIdentifier)  // "com.example.app.dev"
print(env.debugMenu)         // true
```

### Skip Swift Generation

To only generate xcconfig files:
```bash
xp env load dev --skip-swift
```

### Update .gitignore for Swift Files

```gitignore
# Environment management
env/.current
**/Config/*.xcconfig
**/Generated/EnvironmentService*.swift
```

## Advanced Features

### Bundle ID Suffixes

For app extensions (widgets, notification extensions, etc.):

```yaml
targets:
  - name: MyAppWidget
    xcconfig_path: Widgets/Config
    bundle_id_suffix: .widget          # Automatically appends to bundle ID
    shared_variables:
      PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_identifier
```

If `apps.bundle_identifier = com.example.app`, the generated xcconfig will have:
```
PRODUCT_BUNDLE_IDENTIFIER = com.example.app.widget
```

### Per-Configuration Variables

Add configuration-specific variables:

```yaml
targets:
  - name: MyApp
    xcconfig_path: MyApp/Config
    shared_variables:
      # Common to all configurations
      PRODUCT_BUNDLE_IDENTIFIER: apps.bundle_identifier
    configurations:
      debug:
        # Debug-specific variables
      release:
        variables:
          # Release-only variables
          PROVISIONING_PROFILE_SPECIFIER: apps.ios.provision_profile
          ENABLE_BITCODE: "YES"
```

### Nested YAML Variables

Use dot notation to access nested values:

```yaml
# env/dev/env.yml
apps:
  ios:
    settings:
      theme: dark
      locale: en_US

# env/config.yml
variables:
  APP_THEME: apps.ios.settings.theme
  APP_LOCALE: apps.ios.settings.locale
```

## Troubleshooting

### "env/config.yml not found"

Make sure you have:
1. Created `env/config.yml` in your project root
2. Running `xp` from the correct working directory (use `-C` if needed)

### "xcconfig directory not found"

Create the output directory first:
```bash
mkdir -p MyApp/Config
```

### "Variable 'X' not found at path 'Y'"

The variable path in `env/config.yml` doesn't exist in your `env.yml` file. Check:
1. The path is correct (e.g., `apps.bundle_identifier`)
2. The variable exists in all environment files

### "Environment 'X' not found"

Make sure you have:
1. Created `env/X/` directory
2. Created `env/X/env.yml` file

## Best Practices

1. **Keep secrets out of env.yml**: Use environment variables or secure vaults for API keys
2. **Version control env.yml**: Commit environment files, but exclude `.current` and generated `.xcconfig` files
3. **Use meaningful names**: Name environments clearly (dev, staging, production)
4. **Validate often**: Run `xp env validate` before committing changes
5. **Document variables**: Add comments in your env.yml files

## Integration with Xcode

### Link XCConfigs to Xcode

1. Open your project in Xcode
2. Select the project in the navigator
3. Select your target
4. Go to Info tab
5. Under Configurations, set:
   - Debug → `SampleProject.debug.xcconfig`
   - Release → `SampleProject.release.xcconfig`

### Verify Integration

Build settings from xcconfig files will override project settings. Check:
- Product Bundle Identifier
- Display Name
- Any custom variables you've defined

## Example Projects

See `SampleProject/` for a complete working example with:
- Two environments (dev, production)
- Bundle identifier mapping
- App icon configuration
- API URL configuration
