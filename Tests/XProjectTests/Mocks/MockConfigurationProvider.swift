//
// MockConfigurationProvider.swift
// XProject
//

import Foundation
@testable import XProject

/// Mock implementation of ConfigurationProviding for testing
public struct MockConfigurationProvider: ConfigurationProviding {
    private let mockConfiguration: XProjectConfiguration
    private let mockFilePath: String?

    public init(config: XProjectConfiguration, filePath: String? = "mock-config.yml") {
        self.mockConfiguration = config
        self.mockFilePath = filePath
    }

    public var configuration: XProjectConfiguration {
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
