# Xproject

A modern Swift command line tool for Xcode project build automation.

## Installation & Usage

**No external dependencies required!** Xproject runs with just Xcode's built-in Swift tooling.

### Requirements
- **Swift 6.2+** (included with Xcode 16.4+)
- **macOS 15+** (specified in Package.swift platforms)

### Quick Start

1. **Clone or add as git submodule:**
   ```bash
   # Option 1: Clone directly
   git clone https://github.com/diogot/Xproject.git
   cd Xproject

   # Option 2: Add as submodule to your project
   git submodule add https://github.com/diogot/Xproject.git Tools/Xproject
   cd Tools/Xproject
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

# Validate configuration
xp config validate

# Show current configuration with verbose output
xp config show --verbose
```

### Integration with Existing Projects

Add Xproject as a git submodule and create a simple script:

**setup.sh:**
```bash
#!/bin/bash
# Run from project root
Tools/Xproject/.build/release/xp -C . setup
```

**build.sh:**
```bash
#!/bin/bash
# Run from project root
Tools/Xproject/.build/release/xp -C . build --scheme "$1" --clean
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

### 🚧 In Development
- **Release command** - Archive creation, IPA generation, App Store upload
- **Environment management** - Support for different deployment environments
