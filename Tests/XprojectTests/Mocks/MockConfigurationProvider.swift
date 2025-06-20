//
// MockConfigurationProvider.swift
// Xproject
//

import Foundation
@testable import Xproject

/// Mock implementation of ConfigurationProviding for testing
public struct MockConfigurationProvider: ConfigurationProviding {
    private let mockConfiguration: XprojectConfiguration
    private let mockFilePath: String?

    public init(config: XprojectConfiguration, filePath: String? = "mock-config.yml") {
        self.mockConfiguration = config
        self.mockFilePath = filePath
    }

    public var configuration: XprojectConfiguration {
        get throws {
            return mockConfiguration
        }
    }

    public var configurationFilePath: String? {
        get throws {
            return mockFilePath
        }
    }
}
