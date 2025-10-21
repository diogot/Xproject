//
// NestedDictionary.swift
// Xproject
//

import Foundation

/// A utility for accessing nested dictionary values using dot notation paths.
///
/// This type provides convenient access to nested YAML structures loaded by Yams,
/// allowing paths like "apps.ios.icon" instead of manual dictionary traversal.
///
/// Example:
/// ```swift
/// let yaml = [
///     "apps": [
///         "ios": [
///             "icon": "AppIcon"
///         ]
///     ]
/// ]
/// let dict = NestedDictionary(yaml: yaml)
/// let icon = dict.value(at: "apps.ios.icon") // Returns "AppIcon"
/// ```
public struct NestedDictionary: Sendable {
    private let data: [String: YAMLValue]

    /// Initialize with a type-safe YAML dictionary structure
    /// - Parameter yaml: The root dictionary with YAMLValue types
    public init(yaml: [String: YAMLValue]) {
        self.data = yaml
    }

    /// Initialize from raw YAML dictionary (from Yams.load)
    /// - Parameter anyYaml: The root dictionary from YAML parsing
    /// - Throws: YAMLValueError if conversion fails
    public init(anyYaml: [String: Any]) throws {
        var yamlDict: [String: YAMLValue] = [:]
        for (key, value) in anyYaml {
            yamlDict[key] = try YAMLValue(any: value)
        }
        self.data = yamlDict
    }

    /// Access a value at the specified dot-notation path
    ///
    /// - Parameter path: Dot-separated path (e.g., "apps.ios.icon")
    /// - Returns: The value as a String, or nil if not found or cannot be converted
    /// - Throws: `NestedDictionaryError.arrayAccess` if path accesses an array
    public func value(at path: String) throws -> String? {
        let components = path.split(separator: ".").map(String.init)

        guard !components.isEmpty else {
            return nil
        }

        var current: YAMLValue = .dictionary(data)

        // Traverse the path
        for component in components {
            switch current {
            case .array:
                throw NestedDictionaryError.arrayAccess(path: path)
            case .dictionary(let dict):
                guard let next = dict[component] else {
                    // Key not found
                    return nil
                }
                current = next
            default:
                // Hit a terminal value before end of path
                return nil
            }
        }

        // Convert final value to String
        return current.asString()
    }
}

// MARK: - Errors

public enum NestedDictionaryError: Error, LocalizedError {
    case arrayAccess(path: String)

    public var errorDescription: String? {
        switch self {
        case .arrayAccess(let path):
            return "Cannot access array elements in path '\(path)'. Array access is not supported."
        }
    }
}
