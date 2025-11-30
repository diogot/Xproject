# Version Management

This guide explains how to configure your Xcode project to use Xproject's version management system.

## Overview

Xproject's version management provides:
- Automated semantic versioning (major.minor.patch)
- Build numbers calculated from git commit count
- Git integration for commits, tags, and push operations
- Multi-target support (iOS, tvOS)

## Prerequisites

### Configure Xcode Project for agvtool

Xproject uses Apple's `agvtool` for version management. Your Xcode project must be configured correctly.

#### Build Settings

In Xcode, select your project (not target), then **Build Settings**:

1. **Versioning System** (`VERSIONING_SYSTEM`)
   - Set to `apple-generic`

2. **Current Project Version** (`CURRENT_PROJECT_VERSION`)
   - Set to your current build number (e.g., `1`)

**Important:** Do NOT use `MARKETING_VERSION`. agvtool manages the marketing version directly in Info.plist.

#### Info.plist Configuration

```xml
<key>CFBundleShortVersionString</key>
<string>1.0</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
```

- `CFBundleShortVersionString`: Set to the actual version value (e.g., `1.0`). agvtool reads and writes this directly.
- `CFBundleVersion`: Use `$(CURRENT_PROJECT_VERSION)` to reference the build setting.

#### Verify Configuration

Test that agvtool works:

```bash
cd /path/to/your/project
agvtool mvers -terse1        # Should print version (e.g., 1.0.0)
agvtool vers -terse          # Should print build number (e.g., 1)
```

## Configuration

### Xproject.yml

Add the `project_path` and optionally `version` sections:

```yaml
# Required: Map target names to Xcode project paths
project_path:
  ios: MyApp.xcodeproj
  tvos: TV/TV.xcodeproj      # Can be in subdirectory

# Optional: Version configuration
version:
  build_number_offset: 0      # Added to git commit count (default: 0)
  tag_format: "{env}-{target}/{version}-{build}"  # Optional custom format
  inject_build_number: true   # Inject CURRENT_PROJECT_VERSION into xcconfigs
```

### Build Number Injection

When `inject_build_number: true` is set, running `xp env load` will automatically add `CURRENT_PROJECT_VERSION` to all generated xcconfig files. This ensures the app's build number matches what `xp version show` displays.

```yaml
version:
  inject_build_number: true
  build_number_offset: 0
```

The generated xcconfig will include:
```
CURRENT_PROJECT_VERSION = 42
```

#### Xcode Project Setup for Build Number Injection

To use the injected build number, configure your Xcode project:

1. **Reference the xcconfig in your project**

   In Xcode, select your project → Info tab → Configurations. Set the configuration file for each target/configuration to the generated xcconfig (e.g., `MyApp.debug.xcconfig`).

2. **Configure Info.plist**

   Set `CFBundleVersion` to reference the build setting:

   ```xml
   <key>CFBundleVersion</key>
   <string>$(CURRENT_PROJECT_VERSION)</string>
   ```

3. **Workflow**

   Run `xp env load` before building:

   ```bash
   xp env load dev        # Generates xcconfigs with CURRENT_PROJECT_VERSION
   xcodebuild build ...   # Build uses the injected build number
   ```

   The app will now display the git-based build number calculated by `xp version show`.

### Build Number Offset

The build number is calculated as:

```
build_number = git_commit_count + build_number_offset
```

Use offset to:
- Continue from existing build numbers when migrating
- Start with a specific number (e.g., 1000)
- Compensate for repository history changes

Example: If your repo has 500 commits and your last App Store build was 1500:

```yaml
version:
  build_number_offset: 1000  # 500 + 1000 = 1500
```

### Tag Format Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{env}` | Environment name (if provided) | `production` |
| `{target}` | Target name from config | `ios` |
| `{version}` | Marketing version | `1.2.3` |
| `{build}` | Build number | `42` |

Default formats:
- Without environment: `{target}/{version}-{build}` → `ios/1.2.3-42`
- With environment: `{env}-{target}/{version}-{build}` → `production-ios/1.2.3-42`

## Usage

### Show Current Version

```bash
xp version show              # Uses first configured target
xp version show ios          # Specific target
```

Output:
```
Target: ios
Version: 1.2.3
Build: 42
Full Version: 1.2.3-42
```

### Bump Version

```bash
# Preview first
xp version bump patch --dry-run

# Apply
xp version bump patch        # 1.0.0 → 1.0.1
xp version bump minor        # 1.0.0 → 1.1.0
xp version bump major        # 1.0.0 → 2.0.0

# Specific target
xp version bump patch ios
```

### Commit Changes

After bumping, commit the version files:

```bash
xp version commit --dry-run  # Preview
xp version commit            # Commits with [skip ci] prefix
```

The commit message format: `[skip ci] Bump ios version to 1.2.3-42`

### Create Git Tag

```bash
xp version tag --dry-run
xp version tag                              # Creates: ios/1.2.3-42
xp version tag --environment production     # Creates: production-ios/1.2.3-42
```

### Push to Remote

```bash
xp version push --dry-run
xp version push                  # Push to origin
xp version push --remote upstream  # Push to specific remote
```

## Common Workflows

### Standard Release

```bash
# 1. Ensure clean repository
git status

# 2. Bump version
xp version bump patch

# 3. Commit
xp version commit

# 4. Tag
xp version tag --environment production

# 5. Push
xp version push

# 6. Build release
xp release production-ios
```

### Multi-Target Release

```bash
# Bump both targets
xp version bump minor ios
xp version bump minor tvos

# Commit each
xp version commit ios
xp version commit tvos

# Tag each
xp version tag ios --environment production
xp version tag tvos --environment production

# Push once
xp version push
```

### Preview Without Changes

All commands support `--dry-run`:

```bash
xp version bump patch --dry-run
xp version commit --dry-run
xp version tag --dry-run
xp version push --dry-run
```

## Troubleshooting

### agvtool not found

```
Error: agvtool not found in PATH.
```

**Solution:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### Not a git repository

```
Error: Not a git repository.
```

**Solution:** Initialize git or run from correct directory:
```bash
git init
```

### agvtool returns empty version

```
Error: Failed to get version: agvtool returned empty output
```

**Cause:** Project not configured for agvtool.

**Solution:**
1. In Xcode, select the **project** (blue icon, not targets)
2. Go to **Build Settings**
3. Search for "versioning"
4. Set **Versioning System** to `apple-generic`
5. Set **Current Project Version** to a number (e.g., `1`)
6. In Info.plist, set `CFBundleShortVersionString` to the actual version (e.g., `1.0`)

### Modern Xcode Projects (GENERATE_INFOPLIST_FILE)

```
Error: Cannot find "MyProject.xcodeproj/../YES"
```

**Cause:** Projects created in Xcode 13+ often use `GENERATE_INFOPLIST_FILE = YES`, which auto-generates Info.plist. agvtool doesn't support this.

**Solution:** Create a manual Info.plist:

1. Create `Info.plist` in your project directory:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
</dict>
</plist>
```

2. Update build settings:
   - Set `GENERATE_INFOPLIST_FILE = NO`
   - Set `INFOPLIST_FILE = Info.plist`
   - Remove `MARKETING_VERSION` if present

3. Verify:
```bash
agvtool mvers -terse1
```

### Tag already exists

```
Error: Git tag 'ios/1.2.3-42' already exists.
```

**Solution:** Either bump to a new version or delete the existing tag:
```bash
git tag -d ios/1.2.3-42           # Delete local
git push origin :ios/1.2.3-42     # Delete remote (if pushed)
```

### Unexpected changes found

```
Error: Found unexpected uncommitted changes.
Expected files: project.pbxproj, Info.plist
But found changes in: OtherFile.swift
```

**Cause:** Version commit validates that only version-related files changed.

**Solution:** Commit or stash other changes first:
```bash
git stash
xp version commit
git stash pop
```

## Understanding Target vs Project

The "target" parameter in version commands refers to a **configuration key** in `project_path`, not an Xcode build target:

```yaml
project_path:
  ios: MyApp.xcodeproj        # "ios" is the target key
  tvos: TV/TV.xcodeproj       # "tvos" is the target key
```

When you run `xp version bump patch ios`, agvtool updates **all Xcode targets** within `MyApp.xcodeproj`. This matches Apple's agvtool behavior, which operates on entire projects.

## Safety Features

- **Repository clean check**: Warns about uncommitted changes
- **Expected files validation**: Prevents committing unrelated changes with version bump
- **Tag existence check**: Prevents duplicate tags
- **Dry-run mode**: Preview all operations safely
- **[skip ci] commits**: Version commits skip CI pipelines by default
