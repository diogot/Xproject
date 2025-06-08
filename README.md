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

   # Build project
   swift run xp build --scheme MyApp --configuration Release

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
- `xp build` - Build the Xcode project
- `xp test` - Run unit tests
- `xp release` - Create a release build (archive + IPA)
- `xp config` - Manage project configuration

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
swift run xp build --scheme "$1" --configuration Release
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
