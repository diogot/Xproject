//
// TestConstants.swift
// Xproject
//

import Foundation
import Testing

/// Common test constants
public enum TestConstants {
    /// Common test data
    public enum TestData {
        public static let defaultAppName = "TestApp"
        public static let defaultProjectName = "TestProject"
        public static let defaultWorkspaceName = "TestApp.xcworkspace"
        public static let defaultBuildPath = "build"
        public static let defaultReportsPath = "reports"
        public static let defaultXcodeVersion = "16.0"

        /// Common iOS destinations for testing
        public static let iOSDestinations = [
            "platform=iOS Simulator,OS=18.5,name=iPhone 16 Pro",
            "platform=iOS Simulator,OS=17.0,name=iPhone 15",
            "platform=iOS Simulator,OS=16.0,name=iPhone 14"
        ]

        /// Common tvOS destinations for testing
        public static let tvOSDestinations = [
            "platform=tvOS Simulator,OS=18.5,name=Apple TV 4K (3rd generation) (at 1080p)",
            "platform=tvOS Simulator,OS=17.0,name=Apple TV 4K (2nd generation)"
        ]

        /// Common brew formulas for testing
        public static let testBrewFormulas = ["swiftgen", "swiftlint"]
    }

    /// Common error messages for testing
    public enum ErrorMessages {
        public static let configurationNotFound = "Configuration file not found"
        public static let invalidConfiguration = "Invalid configuration"
        public static let buildFailed = "Build failed"
        public static let testsFailed = "Tests failed"
        public static let schemeNotFound = "Scheme not found"
        public static let brewNotInstalled = "Homebrew not found"
    }

    /// Common file paths for testing
    public enum FilePaths {
        public static let testConfigFileName = "test-config.yml"
        public static let invalidConfigFileName = "invalid-config.yml"
        public static let dummyProjectName = "DummyProject.xcodeproj"
    }
}
