//
// LineBufferTests.swift
// Xproject
//

import Foundation
import Testing
@testable import Xproject

@Suite("LineBuffer Tests")
struct LineBufferTests {
    // MARK: - Basic Line Splitting

    @Test("Single complete line returns one line")
    func singleCompleteLine() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("Hello World\n")
        #expect(lines == ["Hello World"])
    }

    @Test("Multiple complete lines returns all lines")
    func multipleCompleteLines() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("Line 1\nLine 2\nLine 3\n")
        #expect(lines == ["Line 1", "Line 2", "Line 3"])
    }

    @Test("Empty string returns no lines")
    func emptyString() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("")
        #expect(lines.isEmpty)
    }

    // MARK: - Partial Line Buffering

    @Test("Partial line without newline is buffered")
    func partialLineBuffered() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("Partial")
        #expect(lines.isEmpty)

        let remaining = await buffer.flush()
        #expect(remaining == "Partial")
    }

    @Test("Partial line completed on next append")
    func partialLineCompleted() async {
        let buffer = LineBuffer()
        var lines = await buffer.append("Hello ")
        #expect(lines.isEmpty)

        lines = await buffer.append("World\n")
        #expect(lines == ["Hello World"])
    }

    @Test("Multiple appends before complete line")
    func multipleAppendsBeforeComplete() async {
        let buffer = LineBuffer()
        var allLines: [String] = []

        allLines += await buffer.append("Part")
        allLines += await buffer.append("ial ")
        allLines += await buffer.append("Line\n")

        #expect(allLines == ["Partial Line"])
    }

    // MARK: - Flush Behavior

    @Test("Flush returns remaining content")
    func flushReturnsRemaining() async {
        let buffer = LineBuffer()
        _ = await buffer.append("Complete\nPartial")

        let remaining = await buffer.flush()
        #expect(remaining == "Partial")
    }

    @Test("Flush on empty buffer returns nil")
    func flushEmptyBuffer() async {
        let buffer = LineBuffer()
        let remaining = await buffer.flush()
        #expect(remaining == nil)
    }

    @Test("Flush after complete lines returns nil")
    func flushAfterCompleteLines() async {
        let buffer = LineBuffer()
        _ = await buffer.append("Line 1\nLine 2\n")

        let remaining = await buffer.flush()
        #expect(remaining == nil)
    }

    @Test("Flush clears buffer")
    func flushClearsBuffer() async {
        let buffer = LineBuffer()
        _ = await buffer.append("Content")

        _ = await buffer.flush()
        let secondFlush = await buffer.flush()
        #expect(secondFlush == nil)
    }

    // MARK: - Edge Cases

    @Test("Consecutive newlines produce empty lines")
    func consecutiveNewlines() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("Line 1\n\n\nLine 2\n")
        #expect(lines == ["Line 1", "", "", "Line 2"])
    }

    @Test("String starting with newline")
    func stringStartingWithNewline() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("\nLine 1\n")
        #expect(lines == ["", "Line 1"])
    }

    @Test("Only newlines")
    func onlyNewlines() async {
        let buffer = LineBuffer()
        let lines = await buffer.append("\n\n\n")
        #expect(lines == ["", "", ""])
    }

    @Test("Mixed complete and partial across appends")
    func mixedCompleteAndPartial() async {
        let buffer = LineBuffer()

        var lines = await buffer.append("First\nSec")
        #expect(lines == ["First"])

        lines = await buffer.append("ond\nThi")
        #expect(lines == ["Second"])

        lines = await buffer.append("rd\n")
        #expect(lines == ["Third"])

        let remaining = await buffer.flush()
        #expect(remaining == nil)
    }
}
