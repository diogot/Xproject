//
// YAMLValue.swift
// Xproject
//

import Foundation

/// Represents all possible YAML value types
public enum YAMLValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: YAMLValue])
    case array([YAMLValue])
    case null

    /// Convert to string representation for xcconfig files
    /// - Returns: String representation, or nil for non-terminal values (dictionaries, arrays)
    public func asString() -> String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .dictionary, .array:
            return nil  // Non-terminal values
        case .null:
            return nil
        }
    }

    /// Initialize from Any (for YAML parsing with Yams)
    /// - Parameter value: Value from YAML parsing
    /// - Throws: YAMLValueError if value cannot be converted to a supported type
    public init(any value: Any) throws {
        if let string = value as? String {
            self = .string(string)
        } else if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let dict = value as? [String: Any] {
            var yamlDict: [String: YAMLValue] = [:]
            for (key, val) in dict {
                yamlDict[key] = try YAMLValue(any: val)
            }
            self = .dictionary(yamlDict)
        } else if let array = value as? [Any] {
            let yamlArray = try array.map { try YAMLValue(any: $0) }
            self = .array(yamlArray)
        } else if value is NSNull {
            self = .null
        } else if let number = value as? NSNumber {
            // Handle NSNumber (from YAML parsing)
            // NSNumber can represent bool, int, or double
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                self = .bool(number.boolValue)
            } else if number.objCType.pointee == 0x64 { // 'd' for double
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        } else {
            throw YAMLValueError.unsupportedType(type: String(describing: type(of: value)))
        }
    }
}

// MARK: - Errors

/// Errors related to YAMLValue conversion
public enum YAMLValueError: Error, LocalizedError {
    case unsupportedType(type: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let type):
            return "Unsupported YAML type: \(type)"
        }
    }
}
