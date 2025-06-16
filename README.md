# XProject

A modern Swift command line tool for Xcode project build automation.

## Installation & Usage

**No external dependencies required!** XProject runs with just Xcode's built-in Swift tooling.

### Quick Start

1. **Clone or add as git submodule:**
   ```bash
   # Option 1: Clone directly
   git clone https://github.com/diogot/XProject.git
   cd XProject

   # Option 2: Add as submodule to your project
   git submodule add https://github.com/diogot/XProject.git Tools/XProject
   cd Tools/XProject
   ```

2. **Run directly with Swift:**
   ```bash
   # Show help
   swift run xp --help

   # Setup project
   swift run xp setup

   # Build project for testing
   swift run xp build --scheme MyApp --clean

   # Run tests
   swift run xp test --scheme MyApp --clean

   # Create release
   swift run xp release production-ios
   ```

3. **Build and install locally (optional):**
   ```bash
   swift build -c release
   cp .build/release/xp /usr/local/bin/xp

   # Now you can use it globally
   xp setup
   ```

### Available Commands

- `xp setup` - Setup project dependencies and environment
- `xp build` - Build the Xcode project for testing
- `xp test` - Run unit tests with multi-destination support
- `xp release` - Create a release build (TODO: Not yet implemented)
- `xp config` - Manage and validate project configuration

### Global Options

All commands support the following global options:
- `--config <path>` - Specify custom configuration file (default: auto-discover XProject.yml, rake-config.yml)
- `--dry-run` - Show what would be done without executing (available on most commands)

### Command Examples

```bash
# Use custom configuration file
xp test --config my-project.yml --dry-run

# Run tests with specific options
xp test --scheme MyApp --clean --destination "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro"

# Setup with dry-run preview
xp setup --dry-run

# Validate configuration
xp config validate

# Show current configuration
xp config show
```

### Integration with Existing Projects

Add XProject as a git submodule and create a simple script:

**setup.sh:**
```bash
#!/bin/bash
cd Tools/XProject
swift run xp setup
```

**build.sh:**
```bash
#!/bin/bash
cd Tools/XProject
swift run xp build --scheme "$1" --clean
```

This approach ensures:
-  No external package managers required
-  Works with just Xcode installation
-  Version-locked to your project via git submodule
-  Same tool version across all team members
-  Works in CI/CD without additional setup

## Development

```bash
# Run tests
swift test

# Build
swift build

# Run in development
swift run xp --help
```

## Features

### ✅ Completed
- **Multi-scheme and multi-destination testing** - Run tests across multiple iOS simulators
- **Custom configuration files** - Use `--config` option to specify project-specific configs
- **Dry-run mode** - Preview operations without executing them (`--dry-run`)
- **Enhanced error handling** - Clear error messages with config file context
- **Legacy compatibility** - Works with existing rake-config.yml files
- **Type-safe configuration** - Swift Codable structs with validation
- **Homebrew integration** - Automated tool installation and updates
- **Clean architecture** - Separated CLI and business logic

### 🚧 In Development
- **Release command** - Archive creation, IPA generation, App Store upload
- **Environment management** - Support for different deployment environments
