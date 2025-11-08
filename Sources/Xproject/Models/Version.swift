//
// Version.swift
// Xproject
//

import Foundation

/// Represents a semantic version with major, minor, and patch components
public struct Version: Sendable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse a version string in format "major.minor.patch" or "major.minor"
    /// - Parameter string: Version string to parse (e.g., "1.2.3" or "1.2")
    /// - Throws: VersionError if the string is invalid
    public init(string: String) throws {
        let components = string.split(separator: ".").map(String.init)

        guard components.count >= 2, components.count <= 3 else {
            throw VersionError.invalidFormat(string)
        }

        guard let major = Int(components[0]),
              let minor = Int(components[1]) else {
            throw VersionError.invalidFormat(string)
        }

        self.major = major
        self.minor = minor

        if components.count == 3 {
            guard let patch = Int(components[2]) else {
                throw VersionError.invalidFormat(string)
            }
            self.patch = patch
        } else {
            self.patch = 0
        }
    }

    /// Create a new version by bumping the specified component
    /// - Parameter type: The bump type (patch, minor, or major)
    /// - Returns: A new version with the specified component incremented
    public func bumped(_ type: BumpType) -> Version {
        switch type {
        case .patch:
            // 1.0.0 → 1.0.1
            return Version(major: major, minor: minor, patch: patch + 1)
        case .minor:
            // 1.0.0 → 1.1.0
            return Version(major: major, minor: minor + 1, patch: 0)
        case .major:
            // 1.0.0 → 2.0.0
            return Version(major: major + 1, minor: 0, patch: 0)
        }
    }

    /// String representation in format "major.minor.patch"
    public var description: String {
        return "\(major).\(minor).\(patch)"
    }

    /// Full version string including build number
    /// - Parameter build: The build number to append
    /// - Returns: Version string in format "major.minor.patch-build"
    public func fullVersion(build: Int) -> String {
        return "\(description)-\(build)"
    }

    public enum BumpType: String, Sendable {
        case patch
        case minor
        case major
    }
}

// MARK: - Version Errors

public enum VersionError: Error, LocalizedError, Sendable {
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let version):
            return """
            Invalid version format: '\(version)'

            ✅ Expected format: major.minor.patch or major.minor
            Examples: 1.2.3, 1.0, 2.1.0
            """
        }
    }
}
