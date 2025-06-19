//
// MockFileManager.swift
// Xproject
//

import Foundation

/// Mock FileManager for testing file system operations
public class MockFileManager: FileManager, @unchecked Sendable {
    public var createdDirectories: [String] = []
    public var removedItems: [String] = []
    public var fileExistsResponses: [String: Bool] = [:]

    override public init() {
        super.init()
    }

    override public func createDirectory(
        atPath path: String,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        createdDirectories.append(path)
    }

    override public func removeItem(atPath path: String) throws {
        removedItems.append(path)
    }

    override public func fileExists(atPath path: String) -> Bool {
        return fileExistsResponses[path] ?? super.fileExists(atPath: path)
    }

    /// Reset all recorded operations
    public func reset() {
        createdDirectories.removeAll()
        removedItems.removeAll()
        fileExistsResponses.removeAll()
    }

    /// Set response for fileExists check
    public func setFileExists(_ exists: Bool, atPath path: String) {
        fileExistsResponses[path] = exists
    }
}
