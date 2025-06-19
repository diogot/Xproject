# Xproject Test Helper Guide

This guide explains the test helpers, mocks, and utilities available for writing tests in Xproject.

## Directory Structure

```
Tests/XprojectTests/
├── Helpers/
│   ├── ConfigurationTestHelper.swift    # Configuration-related test utilities
│   ├── TestAssertions.swift             # Common assertion helpers
│   ├── TestConstants.swift              # Shared constants and tags
│   └── TestFileHelper.swift             # File system test utilities
├── Mocks/
│   ├── MockBuildService.swift           # Mock implementation of BuildServiceProtocol
│   ├── MockCommandExecutor.swift        # Mock command executor
│   ├── MockConfigurationProvider.swift  # Mock implementation of ConfigurationProviding
│   └── MockFileManager.swift            # Mock FileManager for testing
└── Builders/
    ├── XprojectConfigurationBuilder.swift    # Builder for XprojectConfiguration
    ├── XcodeConfigurationBuilder.swift       # Builder for XcodeConfiguration
    └── TestSchemeConfigurationBuilder.swift  # Builder for test schemes
```

## Using Test Helpers

### ConfigurationTestHelper

Provides utilities for working with configurations in tests:

```swift
// Create a test configuration service
let configService = ConfigurationTestHelper.createTestConfigurationService()

// Create a temporary configuration
try ConfigurationTestHelper.withTemporaryConfig(
    appName: "TestApp",
    projectName: "TestProject"
) { configURL, configService in
    // Use the configuration
}

// Create a test configuration with Xcode settings
let config = ConfigurationTestHelper.createTestConfigurationWithXcode()
```

### TestFileHelper

Utilities for working with temporary files and directories:

```swift
// Work with a temporary file
try TestFileHelper.withTemporaryFile(content: "test content") { url in
    // Use the file
}

// Work with a temporary directory
try TestFileHelper.withTemporaryDirectory { tempDir in
    // Use the directory
}

// Create a dummy Xcode project
try TestFileHelper.createDummyProject(in: directory, name: "MyProject")
```

### WorkingDirectoryHelper

Safely change working directories in tests:

```swift
try WorkingDirectoryHelper.withTemporaryWorkingDirectory { 
    // Code runs in temporary directory
    // Original directory is restored after
}
```

## Using Mocks

### MockConfigurationProvider

```swift
let config = XprojectConfigurationBuilder.minimal()
let mockProvider = MockConfigurationProvider(config: config)
let service = BuildService(configurationProvider: mockProvider)
```

### MockBuildService

```swift
let mockBuildService = MockBuildService()
await mockBuildService.setShouldFailBuildForScheme("MyScheme", shouldFail: true)
let testService = TestService(buildService: mockBuildService)
```

### MockFileManager

```swift
let mockFileManager = MockFileManager()
mockFileManager.setFileExists(true, atPath: "/some/path")
// Use in service that accepts FileManager
```

### MockCommandExecutor

```swift
let mockExecutor = MockCommandExecutor()
mockExecutor.setResponse(for: "echo test", response: .success)
mockExecutor.setCommandExists("brew", exists: true)
```

## Using Builders

### XprojectConfigurationBuilder

```swift
// Minimal configuration
let config = XprojectConfigurationBuilder.minimal()

// Custom configuration
let config = XprojectConfigurationBuilder()
    .withAppName("MyApp")
    .withProjectPath(key: "ios", path: "iOS/MyApp.xcodeproj")
    .withBrewSetup(enabled: true, formulas: ["swiftgen"])
    .build()

// Full test setup
let config = XprojectConfigurationBuilder.fullTestSetup()
```

### TestSchemeConfigurationBuilder

```swift
// iOS scheme
let iosScheme = TestSchemeConfigurationBuilder.ios().build()

// Custom scheme
let customScheme = TestSchemeConfigurationBuilder()
    .withScheme("MyScheme")
    .withBuildDestination("generic/platform=iOS")
    .withTestDestinations(["platform=iOS Simulator,OS=18.5,name=iPhone 16"])
    .build()
```

## Using Test Assertions

### Custom Assertions

```swift
// Assert specific error type
TestAssertions.assertThrows(
    ConfigurationError.self,
    containingMessage: "Invalid configuration"
) {
    try someOperation()
}

// Assert no error
let result = TestAssertions.assertNoThrow {
    try someOperation()
}

// Assert command execution
TestAssertions.assertCommandExecuted(
    mockExecutor,
    command: "brew install",
    containing: "swiftgen"
)

// Assert file system operations
TestAssertions.assertDirectoryCreated(mockFileManager, path: "/build")
TestAssertions.assertItemRemoved(mockFileManager, path: "/temp")
```

## Using Test Constants

### Tags

```swift
@Test("My test", .tags(TestConstants.Tags.unit, TestConstants.Tags.fast))
func myTest() {
    // Test implementation
}
```

### Test Data

```swift
let destination = TestConstants.TestData.iOSDestinations.first!
let appName = TestConstants.TestData.defaultAppName
```

## Best Practices

1. **Use builders for complex objects**: Instead of manually creating configurations, use the builder pattern for clarity and maintainability.

2. **Prefer helper methods over direct construction**: Use `ConfigurationTestHelper.createTestConfigurationService()` instead of manually setting up configurations.

3. **Use appropriate tags**: Tag your tests appropriately for better organization and filtering.

4. **Clean up resources**: The helpers automatically clean up temporary files and directories, but ensure you're using the `with*` methods that handle cleanup.

5. **Mock external dependencies**: Always mock command execution, file system operations, and network calls in unit tests.

6. **Use custom assertions**: The custom assertions provide better error messages and reduce boilerplate.

## Example Test

```swift
import Testing
@testable import Xproject

@Suite("MyService Tests", .tags(TestConstants.Tags.unit, TestConstants.Tags.fast))
struct MyServiceTests {
    @Test("Service executes command correctly")
    func testCommandExecution() throws {
        // Arrange
        let mockExecutor = MockCommandExecutor()
        mockExecutor.setResponse(for: "echo test", response: .success)
        
        let config = XprojectConfigurationBuilder.minimal()
        let mockProvider = MockConfigurationProvider(config: config)
        
        let service = MyService(
            configurationProvider: mockProvider,
            commandExecutor: mockExecutor
        )
        
        // Act
        try service.performOperation()
        
        // Assert
        TestAssertions.assertCommandExecuted(mockExecutor, command: "echo test")
    }
}
```