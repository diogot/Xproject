# Secret Management User Guide

This guide explains how to set up and use the secret management system in Xproject.

## Overview

The secret management system provides dual-layer security for your API keys and sensitive data:

1. **EJSON Encryption (At-Rest)**: Asymmetric encryption using NaCl Box (Curve25519) protects secrets in your repository
2. **XOR Obfuscation (In-Binary)**: Prevents extraction of secrets using `strings` command on compiled binaries

This approach is inspired by [cocoapods-keys](https://github.com/orta/cocoapods-keys) and provides defense-in-depth security.

## Directory Structure

```
YourProject/
├── env/
│   ├── dev/
│   │   ├── env.yml              # Environment variables
│   │   └── keys.ejson           # Encrypted secrets (safe to commit)
│   ├── staging/
│   │   └── keys.ejson
│   └── production/
│       └── keys.ejson
├── MyApp/
│   └── Generated/
│       └── AppKeys.swift        # Generated obfuscated code (gitignored)
└── Xproject.yml                 # Enable with secrets.enabled: true
```

## Quick Start

### 1. Enable Secret Management

Add to your `Xproject.yml`:

```yaml
secrets:
  enabled: true
  swift_generation:
    outputs:
      - path: MyApp/Generated/AppKeys.swift
        prefixes: [all, ios]
```

### 2. Create EJSON Key Pair

Generate a new key pair for your environment:

```bash
# The key pair will be displayed - save the private key securely!
xp secrets generate-keys dev
```

This creates `env/dev/keys.ejson` with:
```json
{
  "_public_key": "64-char-hex-public-key",
  "all_api_key": "your_secret_value"
}
```

### 3. Store Private Key

Choose one of these options:

**Option A: Environment Variable (Recommended for CI/CD)**
```bash
export EJSON_PRIVATE_KEY_DEV="your-64-char-hex-private-key"
# Or global fallback:
export EJSON_PRIVATE_KEY="your-64-char-hex-private-key"
```

**Option B: macOS Keychain (Recommended for local development)**
```bash
security add-generic-password \
  -s "dev.xproject.ejson.YourAppName" \
  -a "dev" \
  -w "your-64-char-hex-private-key"
```

**Option C: Interactive Prompt**
If no key is found, Xproject will prompt you interactively (when running in a terminal).

### 4. Add Your Secrets

Edit `env/dev/keys.ejson` to add secrets:

```json
{
  "_public_key": "64-char-hex-public-key",
  "all_api_key": "sk_live_1234567890",
  "ios_bundle_secret": "ios-specific-secret",
  "services_analytics_key": "analytics-api-key"
}
```

### 5. Encrypt Secrets

```bash
xp secrets encrypt dev
# Or encrypt all environments:
xp secrets encrypt
```

### 6. Generate Swift Code

```bash
xp secrets generate dev
```

Or automatically during environment load:
```bash
xp env load dev
```

## Available Commands

| Command | Description |
|---------|-------------|
| `xp secrets generate-keys <env>` | Generate new EJSON keypair for environment |
| `xp secrets generate <env>` | Generate obfuscated AppKeys.swift |
| `xp secrets encrypt [env]` | Encrypt EJSON files |
| `xp secrets decrypt <env>` | Decrypt and display secrets (dev only) |
| `xp secrets show <env>` | Display encrypted file info |
| `xp secrets validate [env]` | Validate EJSON file structure |

### Command Examples

```bash
# Generate new keypair for an environment
xp secrets generate-keys dev

# Generate keypair and save to Keychain
xp secrets generate-keys dev --save-to-keychain

# Overwrite existing keys
xp secrets generate-keys dev --force

# View encrypted file information
xp secrets show dev

# Validate all EJSON files
xp secrets validate

# Preview generation without writing files
xp secrets generate dev --dry-run

# Encrypt specific environment
xp secrets encrypt production
```

## Prefix Filtering

Secrets can be filtered by prefix for different targets:

| Prefix | Example Key | Use Case |
|--------|-------------|----------|
| `all_` | `all_api_key` | Shared across all platforms |
| `ios_` | `ios_push_cert` | iOS-specific secrets |
| `tvos_` | `tvos_bundle_id` | tvOS-specific secrets |
| `services_` | `services_firebase_key` | Backend services |

Configure outputs in `Xproject.yml`:

```yaml
secrets:
  enabled: true
  swift_generation:
    outputs:
      - path: MyApp/Generated/AppKeys.swift
        prefixes: [all, ios]
      - path: MyTVApp/Generated/AppKeys.swift
        prefixes: [all, tvos]
```

## Generated Swift Code

The generated `AppKeys.swift` contains obfuscated byte arrays:

```swift
import Foundation

final class AppKeys {
    // Private: obfuscated byte arrays (random XOR)
    private static let _apiKey: [UInt8] = [135, 89, 20, 175, ...]

    // Public: deobfuscated accessors
    static var apiKey: String {
        String(bytes: _apiKey.deobfuscated, encoding: .utf8)!
    }
}

private extension Array where Element == UInt8 {
    var deobfuscated: [UInt8] {
        let half = count / 2
        return zip(prefix(half), suffix(half)).map(^)
    }
}
```

### Key Features

- **CamelCase conversion**: `api_key` becomes `apiKey`
- **URL suffix handling**: `api_url` becomes `apiURL`
- **Type inference**: URLs detected by suffix, booleans, integers
- **No plaintext**: Secrets stored as XOR-obfuscated byte arrays

## CI/CD Integration

### Environment Variables

Set these in your CI/CD environment:

```bash
# Per-environment keys (recommended)
EJSON_PRIVATE_KEY_DEV="64-char-hex-key"
EJSON_PRIVATE_KEY_STAGING="64-char-hex-key"
EJSON_PRIVATE_KEY_PRODUCTION="64-char-hex-key"

# Or single global key
EJSON_PRIVATE_KEY="64-char-hex-key"
```

### Priority Order

1. `EJSON_PRIVATE_KEY_{ENVIRONMENT}` (e.g., `EJSON_PRIVATE_KEY_PRODUCTION`)
2. `EJSON_PRIVATE_KEY` (global fallback)
3. macOS Keychain
4. Interactive prompt (if TTY available)
5. Error

### GitHub Actions Example

```yaml
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate secrets
        env:
          EJSON_PRIVATE_KEY_PRODUCTION: ${{ secrets.EJSON_PRIVATE_KEY_PRODUCTION }}
        run: |
          xp secrets generate production
          xp env load production
```

## Keychain Setup

### Store a Key

```bash
# Using security command
security add-generic-password \
  -s "dev.xproject.ejson.YourAppName" \
  -a "dev" \
  -w "your-64-char-hex-private-key"

# Using Keychain Access app
# 1. Open Keychain Access
# 2. File > New Password Item
# 3. Service: dev.xproject.ejson.YourAppName
# 4. Account: dev (or your environment name)
# 5. Password: your 64-character hex private key
```

### Retrieve a Key

```bash
security find-generic-password \
  -s "dev.xproject.ejson.YourAppName" \
  -a "dev" \
  -w
```

### Delete a Key

```bash
security delete-generic-password \
  -s "dev.xproject.ejson.YourAppName" \
  -a "dev"
```

## Validation

Validate your EJSON files without requiring the private key:

```bash
# Validate all environments
xp secrets validate

# Validate specific environment
xp secrets validate dev
```

Validation checks:
- File exists and contains valid JSON
- Public key is present and valid (64-char hex)
- Reports encryption status of each secret

Example output:
```
✓ dev (env/dev/keys.ejson)
  Public Key: a1b2c3d4e5f6g7h8...
  Secrets: 5 total, 5 encrypted, 0 plaintext

✓ production (env/production/keys.ejson)
  Public Key: i9j0k1l2m3n4o5p6...
  Secrets: 5 total, 4 encrypted, 1 plaintext
  ⚠ WARNING: Secret 'debug_mode' is not encrypted

✓ All EJSON files are valid
```

## Troubleshooting

### "Private key not found" Error

1. Check environment variables are set:
   ```bash
   echo $EJSON_PRIVATE_KEY_DEV
   ```

2. Check keychain entry exists:
   ```bash
   security find-generic-password -s "dev.xproject.ejson.YourAppName" -a "dev"
   ```

3. Verify key format (64 hex characters):
   ```bash
   echo -n "$EJSON_PRIVATE_KEY_DEV" | wc -c
   # Should output: 64
   ```

### "Invalid EJSON format" Error

1. Validate the JSON syntax:
   ```bash
   cat env/dev/keys.ejson | python3 -m json.tool
   ```

2. Ensure `_public_key` field exists:
   ```bash
   xp secrets show dev
   ```

### "Decryption failed" Error

1. Verify private key matches public key in file
2. Check for corrupted encrypted values (should start with `EJ[1:`)
3. Try re-encrypting: `xp secrets encrypt dev`

### Secrets Not Appearing in Generated Code

1. Check prefix configuration in `Xproject.yml`
2. Ensure secret key starts with configured prefix (e.g., `all_`, `ios_`)
3. Run with verbose output: `xp secrets generate dev --verbose`

## Security Considerations

### What This System Protects Against

| Threat | EJSON | XOR Obfuscation |
|--------|-------|-----------------|
| Source code leak | Protected | N/A |
| `strings` extraction | N/A | Protected |
| Binary analysis | N/A | Harder |
| Automated scanning | Protected | Protected |

### What This System Does NOT Protect Against

- Runtime debugging (LLDB, Frida)
- Memory dumps during execution
- Determined reverse engineering
- Jailbroken device inspection

### Best Practices

1. **Never store critical secrets in apps** - Use OAuth, server-side auth
2. **Rotate keys regularly** - Assume compromise is possible
3. **Use certificate pinning** - Protect network communications
4. **Implement jailbreak detection** - For high-security apps
5. **Log secret access** - Monitor for unusual patterns

### Files to Gitignore

```gitignore
# Secret management
**/Generated/AppKeys*.swift
env/*/.ejson_keypair
env/*/keys.json
```

**Note:** Encrypted `keys.ejson` files are safe to commit - they contain only the public key and encrypted data.

## Migration from Ruby Rake

### Equivalent Commands

| Ruby Rake Command | Xproject Command |
|-------------------|------------------|
| `rake ejson:encrypt` | `xp secrets encrypt` |
| `rake env:load[dev]` | `xp env load dev` (auto-includes secrets) |
| N/A | `xp secrets validate` |

### Key Differences

1. **Binary Security**: XOR obfuscation prevents `strings` extraction (Ruby doesn't have this)
2. **Native Swift**: No external tool dependencies
3. **Better Integration**: Secrets generated automatically during `xp env load`
4. **Validation**: New `xp secrets validate` command
5. **Interactive Mode**: Prompt for private key if not found
