import XCTest
@testable import WhisperPTTCore

final class TranscriptHistoryTests: XCTestCase {
    func testHistorySurvivesMultipleSessionsAndPreservesOriginalText() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        XCTAssertEqual(try TranscriptHistory.load(from: file), [])

        let first = HistoryEntry(text: "你好，保留原文。\nSecond line with \"quotes\" and \\slashes.", model: "base", date: Date(timeIntervalSince1970: 1_700_000_000))
        try TranscriptHistory.save([first], to: file)
        var nextSession = try TranscriptHistory.load(from: file)
        XCTAssertEqual(nextSession, [first])
        let second = HistoryEntry(text: "Another recording 🙂", model: "tiny", date: Date(timeIntervalSince1970: 1_700_000_010))
        nextSession.append(second)
        try TranscriptHistory.save(nextSession, to: file)
        XCTAssertEqual(try TranscriptHistory.load(from: file), [first, second])
    }

    func testRepeatedTranscriptsAreAllRetained() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        let entry = HistoryEntry(text: "Repeat this.", model: "base", date: Date(timeIntervalSince1970: 1_700_000_000))
        try TranscriptHistory.save([entry, entry], to: file)
        XCTAssertEqual(try TranscriptHistory.load(from: file), [entry, entry])
    }

    func testMalformedHistoryThrowsWithoutChangingTheFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("history.json")
        let original = Data("broken JSON with existing text".utf8)
        try original.write(to: file)
        XCTAssertThrowsError(try TranscriptHistory.load(from: file))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testSaveFailureIsReported() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let entry = HistoryEntry(text: "Keep the failure visible.", model: "base")
        XCTAssertThrowsError(try TranscriptHistory.save([entry], to: file))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
