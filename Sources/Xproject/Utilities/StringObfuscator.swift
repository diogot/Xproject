//
// StringObfuscator.swift
// Xproject
//
// Provides XOR-based string obfuscation for protecting secrets in compiled binaries.
// This prevents secrets from being extracted with the `strings` command.
//
// Security note: This is obfuscation, not encryption. It raises the bar for casual
// inspection but won't prevent determined reverse engineering. For full security,
// combine with EJSON encryption (at-rest) and avoid storing critical secrets in apps.
//

import Foundation

/// Utility for obfuscating strings using XOR with random data
///
/// This prevents secrets from appearing as plaintext in compiled binaries,
/// making them harder to extract with tools like `strings`.
public enum StringObfuscator: Sendable {
    /// Obfuscates a string using XOR with random data
    ///
    /// The obfuscation works by:
    /// 1. Converting the string to UTF-8 bytes
    /// 2. Generating random bytes of the same length
    /// 3. XORing each byte with its corresponding random byte
    /// 4. Concatenating the XORed result with the random key
    ///
    /// To deobfuscate, split the array in half and XOR the two halves together.
    ///
    /// - Parameter string: The string to obfuscate
    /// - Returns: Byte array in format [xored_bytes..., random_key_bytes...]
    ///
    /// Example:
    /// ```swift
    /// let secret = "sk_live_1234567890"
    /// let obfuscated = StringObfuscator.obfuscate(secret)
    /// // obfuscated = [135, 89, 20, 175, ..., 243, 45, 112, 206, ...]
    /// //               ^^^^^^^^^ XORed data ^^^^^^^^  ^^^^^ Random key ^^^^^
    /// ```
    public static func obfuscate(_ string: String) -> [UInt8] {
        // Convert string to UTF-8 bytes
        guard let data = string.data(using: .utf8) else {
            return []
        }
        let clearBytes = [UInt8](data)

        // Generate random bytes of the same length
        let randomBytes = (0..<clearBytes.count).map { _ in UInt8.random(in: 0...255) }

        // XOR each byte with its corresponding random byte
        let xoredBytes = zip(clearBytes, randomBytes).map(^)

        // Combine XORed result with random key
        return xoredBytes + randomBytes
    }
}

/// Extension to deobfuscate byte arrays back to original data
///
/// This extension is included in generated Swift code to allow runtime deobfuscation.
public extension Array where Element == UInt8 {
    /// Deobfuscates a byte array that was obfuscated using StringObfuscator
    ///
    /// Splits the array in half and XORs the two halves together to recover
    /// the original bytes.
    ///
    /// - Returns: The original byte array
    ///
    /// Example:
    /// ```swift
    /// private static let _apiKey: [UInt8] = [135, 89, 20, ..., 243, 45, 112, ...]
    /// static var apiKey: String {
    ///     String(bytes: _apiKey.deobfuscated, encoding: .utf8)!
    /// }
    /// ```
    var deobfuscated: [UInt8] {
        guard !isEmpty, count % 2 == 0 else {
            return []
        }

        let halfCount = count / 2
        let xoredHalf = prefix(halfCount)
        let keyHalf = suffix(halfCount)

        // XOR the two halves to recover original bytes
        return zip(xoredHalf, keyHalf).map(^)
    }
}
