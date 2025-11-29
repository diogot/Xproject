# Provisioning Profile Management

This guide covers the provisioning profile management system in Xproject, which provides encrypted storage for provisioning profiles for CI/CD with manual signing workflows.

## Overview

The provisioning profile management system allows you to:
- Encrypt provisioning profiles for secure storage in version control
- Decrypt and extract profiles on CI/CD runners
- Install profiles to the system provisioning profiles directory
- Manage profile archives with atomic operations

### Security Model

Profiles are encrypted using **AES-256-CBC** with **PBKDF2** key derivation (100,000 iterations) via the system's `/usr/bin/openssl`. This provides:
- Strong encryption at rest
- Password-based key derivation resistant to brute force
- Cross-platform compatibility (works on all macOS versions)
- No external dependencies beyond macOS built-in tools

### Use Case

This system is designed for:
- CI/CD pipelines that need provisioning profiles for manual signing
- Teams that want to store profiles securely in version control
- Workflows where profiles change infrequently (2-3 times per year)

## Quick Start

### 1. Enable in Configuration

Add to your `Xproject.yml`:

```yaml
provision:
  source_path: provision/source/       # Where to find .mobileprovision files
  archive_path: provision/profiles.zip.enc  # Encrypted archive location
  extract_path: provision/profiles/    # Where to extract decrypted profiles
```

### 2. Set Password

Choose one of these methods:

```bash
# Option 1: Environment variable (recommended for CI/CD)
export PROVISION_PASSWORD="your-secure-password"

# Option 2: macOS Keychain (recommended for local development)
security add-generic-password -s dev.xproject.provision.YourAppName \
    -a provision -w "your-secure-password"
```

### 3. Add Profiles and Encrypt

```bash
# Copy .mobileprovision files to source directory
cp ~/Downloads/*.mobileprovision provision/source/

# Encrypt profiles
xp provision encrypt

# Commit the encrypted archive
git add provision/profiles.zip.enc
git commit -m "Add encrypted provisioning profiles"
```

### 4. Decrypt and Install (CI/CD)

```bash
# Decrypt profiles
xp provision decrypt

# Install to system
xp provision install

# Clean up decrypted files
xp provision cleanup
```

## Configuration Reference

### Xproject.yml Options

```yaml
provision:
  source_path: provision/source/          # Source directory for encryption
  archive_path: provision/profiles.zip.enc  # Encrypted archive path
  extract_path: provision/profiles/       # Extraction directory

  # Optional: Profile metadata (for documentation)
  profiles:
    ios:
      - name: "iOS Development"
        file: "iOS_Development.mobileprovision"
      - name: "iOS Distribution"
        file: "iOS_Distribution.mobileprovision"
    tvos:
      - name: "tvOS Development"
        file: "tvOS_Development.mobileprovision"
```

### Default Paths

If not specified in configuration:
- `source_path`: `provision/source/`
- `archive_path`: `provision/profiles.zip.enc`
- `extract_path`: `provision/profiles/`

## Available Commands

### xp provision encrypt

Encrypts provisioning profiles into an archive.

```bash
# Encrypt from configured source path
xp provision encrypt

# Encrypt from custom source path
xp provision encrypt --source ~/Profiles

# Preview what would be encrypted
xp provision encrypt --dry-run
```

**Options:**
- `--source <path>`: Custom source directory
- `--dry-run`: Show what would be encrypted without creating archive

### xp provision decrypt

Decrypts the profile archive and extracts files.

```bash
# Decrypt to configured extract path
xp provision decrypt

# Preview extraction
xp provision decrypt --dry-run
```

**Options:**
- `--dry-run`: Show what would be extracted without decrypting

### xp provision list

Lists profiles in the encrypted archive.

```bash
xp provision list
```

This command decrypts the archive temporarily to read its contents, then cleans up.

### xp provision install

Installs decrypted profiles to the system provisioning profiles directory.

```bash
# Install profiles
xp provision install

# Preview what would be installed
xp provision install --dry-run
```

**Target Directory:** `~/Library/MobileDevice/Provisioning Profiles/`

**Options:**
- `--dry-run`: Show what would be installed without copying files

**Behavior:**
- Creates target directory if it doesn't exist
- Skips profiles that are already installed and identical
- Reports installed and skipped counts

### xp provision cleanup

Removes decrypted profiles and staging files.

```bash
# Clean up
xp provision cleanup

# Preview cleanup
xp provision cleanup --dry-run
```

**Options:**
- `--dry-run`: Show what would be removed without deleting

## Password Management

### Priority Order

The system checks for the password in this order:
1. Environment variable: `PROVISION_PASSWORD`
2. macOS Keychain (service: `dev.xproject.provision.<app_name>`, account: `provision`)
3. Interactive prompt (if TTY available)
4. Error if not found

### Environment Variable (CI/CD)

Set `PROVISION_PASSWORD` in your CI/CD environment:

```bash
# GitHub Actions
env:
  PROVISION_PASSWORD: ${{ secrets.PROVISION_PASSWORD }}

# GitLab CI
variables:
  PROVISION_PASSWORD: $PROVISION_PASSWORD
```

### Keychain Storage (Local Development)

Store password in keychain for local development:

```bash
# Add password (replace YourAppName with your app_name from config)
security add-generic-password -s dev.xproject.provision.YourAppName \
    -a provision -w "your-password"

# Delete password
security delete-generic-password -s dev.xproject.provision.YourAppName \
    -a provision
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Release

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Xproject
        run: brew install xproject

      - name: Decrypt Provisioning Profiles
        env:
          PROVISION_PASSWORD: ${{ secrets.PROVISION_PASSWORD }}
        run: |
          xp provision decrypt
          xp provision install

      - name: Build and Release
        run: xp release production-ios

      - name: Cleanup
        if: always()
        run: xp provision cleanup
```

### GitLab CI Example

```yaml
build:
  stage: build
  tags:
    - macos

  variables:
    PROVISION_PASSWORD: $PROVISION_PASSWORD

  script:
    - xp provision decrypt
    - xp provision install
    - xp release production-ios

  after_script:
    - xp provision cleanup
```

## Workflow Examples

### Adding New Profiles

```bash
# 1. Copy new profiles to source directory
cp ~/Downloads/New_Profile.mobileprovision provision/source/

# 2. Encrypt all profiles
xp provision encrypt

# 3. Commit the updated archive
git add provision/profiles.zip.enc
git commit -m "Add new provisioning profile"
```

### Updating Profiles

```bash
# 1. Replace profile in source directory
cp ~/Downloads/Updated_Profile.mobileprovision provision/source/

# 2. Re-encrypt
xp provision encrypt

# 3. Commit
git add provision/profiles.zip.enc
git commit -m "Update provisioning profile"
```

### Verifying Profiles

```bash
# List profiles in archive
xp provision list

# Decrypt and check contents
xp provision decrypt
ls -la provision/profiles/
xp provision cleanup
```

## Directory Structure

```
YourProject/
├── provision/
│   ├── source/                    # Source profiles (gitignored)
│   │   ├── iOS_Dev.mobileprovision
│   │   └── iOS_Dist.mobileprovision
│   ├── profiles/                  # Extracted profiles (gitignored)
│   │   └── (decrypted .mobileprovision files)
│   └── profiles.zip.enc           # Encrypted archive (committed)
├── tmp/
│   └── provision/                 # Staging area (gitignored)
└── Xproject.yml
```

## .gitignore Configuration

Add to your `.gitignore`:

```gitignore
# Provisioning profiles
provision/source/
provision/profiles/
tmp/provision/
*.mobileprovision

# The encrypted archive CAN be committed
# provision/profiles.zip.enc
```

## Troubleshooting

### Wrong Password Error

```
Error: Wrong password for encrypted archive.
```

**Solutions:**
- Verify `PROVISION_PASSWORD` is set correctly
- Check keychain entry matches expected service/account names
- Re-encrypt archive with correct password

### Archive Not Found

```
Error: Encrypted provisioning profile archive not found
```

**Solutions:**
- Run `xp provision encrypt` to create the archive
- Check `archive_path` in configuration matches actual location
- Verify archive was committed to version control

### No Profiles Found

```
Error: No .mobileprovision files found
```

**Solutions:**
- Add `.mobileprovision` files to the source directory
- Check `source_path` in configuration is correct
- Verify files have correct extension (case-sensitive)

### OpenSSL Not Found

```
Error: OpenSSL not found at /usr/bin/openssl
```

**Solutions:**
- Reinstall Xcode Command Line Tools: `xcode-select --install`
- OpenSSL should be available on all macOS installations

### Decryption Failed

```
Error: Failed to decrypt provisioning profiles
```

**Solutions:**
- Verify password is correct
- Check archive file is not corrupted
- Try re-encrypting from original profiles

## Security Considerations

1. **Password Strength**: Use a strong, unique password for encryption
2. **Secure Storage**: Store passwords securely (CI/CD secrets, keychain)
3. **Access Control**: Limit who can access the private password
4. **Rotation**: Rotate passwords periodically
5. **Cleanup**: Always clean up decrypted files after use
6. **Audit**: Log profile installation for audit purposes

### What's Protected

- Provisioning profiles encrypted at rest in repository
- Password not exposed in process list (passed via environment)

### What's NOT Protected

- Profiles in memory during decryption/installation
- Installed profiles on disk (standard system permissions apply)
- CI/CD logs may show file operations (not content)

## Migration from Manual Process

If you're currently managing profiles manually:

1. Collect all `.mobileprovision` files into `provision/source/`
2. Enable provision management in `Xproject.yml`
3. Set up password storage (keychain or CI/CD secrets)
4. Run `xp provision encrypt`
5. Commit the encrypted archive
6. Update CI/CD pipeline to use `xp provision decrypt/install`
