//
// TestFileHelper.swift
// XProject
//

import Foundation

public struct TestFileHelper {
    public static func withTemporaryFile<T>(
        content: String,
        fileName: String? = nil,
        fileExtension: String = "yml",
        perform: (URL) throws -> T
    ) throws -> T {
        let fileName = fileName ?? UUID().uuidString
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(fileName).\(fileExtension)")

        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try perform(tempURL)
    }

    public static func withTemporaryDirectory<T>(
        perform: (URL) throws -> T
    ) throws -> T {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try perform(tempDir)
    }

    @discardableResult
    public static func createDummyProject(in directory: URL, name: String) throws -> URL {
        let projectURL = directory.appendingPathComponent("\(name).xcodeproj")
        try "dummy project".write(to: projectURL, atomically: true, encoding: .utf8)
        return projectURL
    }

    @discardableResult
    public static func ensureDummyProject(at path: URL, name: String = "DummyProject") -> URL {
        let projectURL = path.appendingPathComponent("\(name).xcodeproj")
        if !FileManager.default.fileExists(atPath: projectURL.path) {
            let dummyContent = """
                // Dummy project file for testing
                // This file exists solely to provide a valid project path for tests
                // that need to reference an existing file during test execution
                """
            try? dummyContent.write(to: projectURL, atomically: true, encoding: .utf8)
        }
        return projectURL
    }
}
