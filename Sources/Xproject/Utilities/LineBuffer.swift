//
// LineBuffer.swift
// Xproject
//

import Foundation

/// Actor for buffering partial lines during streaming output processing.
/// Used by CommandExecutor for line-by-line output processing.
actor LineBuffer {
    private var buffer = ""

    /// Appends a string to the buffer and returns complete lines.
    /// Incomplete lines (without newline) remain in the buffer.
    func append(_ string: String) -> [String] {
        buffer.append(string)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineIndex])
            lines.append(line)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }

        return lines
    }

    /// Flushes any remaining content in the buffer.
    /// Returns nil if the buffer is empty.
    func flush() -> String? {
        guard !buffer.isEmpty else {
            return nil
        }
        let remaining = buffer
        buffer = ""
        return remaining
    }
}
