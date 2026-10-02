import XCTest
@testable import WhisperPTTCore

final class AppStorageTests: XCTestCase {
    func testExistingDataMovesAndDeletingTheFolderResetsTheApp() throws {
        try withStorage { root, legacy, defaults in
            defaults.set("large-v3_turbo", forKey: "model")
            defaults.set("fn", forKey: "hotkey")
            let model = ModelStorage.folder("base", root: legacy)
            try write(Data([1, 2, 3, 4]), to: model.appendingPathComponent("weights"))
            try write(Data("[{\"type\":\"file\",\"path\":\"openai_whisper-base/weights\",\"size\":4}]".utf8),
                      to: legacy.appendingPathComponent("model-info/base.json"))
            try write(Data([7]), to: legacy.appendingPathComponent("models/shared-tokenizer/tokenizer.json"))
            let partial = "models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/openai_whisper-tiny/weights.incomplete"
            try write(Data([8, 9]), to: legacy.appendingPathComponent(partial))
            let entry = HistoryEntry(text: "Existing history 你好", model: "base", date: Date(timeIntervalSince1970: 1_700_000_000))
            try TranscriptHistory.save([entry], to: root.appendingPathComponent("history.json"))

            let settings = try AppStorage.prepare(root: root, legacyModels: legacy, defaults: defaults)
            XCTAssertEqual(settings, AppSettings(model: "large-v3_turbo", hotkey: "fn"))
            let cache = root.appendingPathComponent("huggingface")
            XCTAssertTrue(ModelStorage.info("base", root: cache).isDownloaded)
            XCTAssertEqual(try Data(contentsOf: cache.appendingPathComponent("models/shared-tokenizer/tokenizer.json")), Data([7]))
            XCTAssertEqual(try Data(contentsOf: cache.appendingPathComponent(partial)), Data([8, 9]))
            XCTAssertEqual(try TranscriptHistory.load(from: root.appendingPathComponent("history.json")), [entry])
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
            XCTAssertNil(defaults.string(forKey: "model"))
            XCTAssertNil(defaults.string(forKey: "hotkey"))

            try FileManager.default.removeItem(at: root)
            XCTAssertEqual(try AppStorage.prepare(root: root, legacyModels: legacy, defaults: defaults), AppSettings())
            XCTAssertEqual(try TranscriptHistory.load(from: root.appendingPathComponent("history.json")), [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        }
    }

    func testSettingsPersistAcrossLaunches() throws {
        try withStorage { root, legacy, defaults in
            XCTAssertEqual(try AppStorage.prepare(root: root, legacyModels: legacy, defaults: defaults), AppSettings())
            let settings = AppSettings(model: "tiny", hotkey: "f13")
            try AppStorage.saveSettings(settings, root: root)
            XCTAssertEqual(try AppStorage.prepare(root: root, legacyModels: legacy, defaults: defaults), settings)
        }
    }

    func testMalformedSettingsDoNotOverwriteDataOrMoveModels() throws {
        try withStorage { root, legacy, defaults in
            defaults.set("fn", forKey: "hotkey")
            let original = Data("malformed settings".utf8)
            try write(original, to: root.appendingPathComponent("settings.json"))
            try write(Data([1]), to: legacy.appendingPathComponent("weights"))
            XCTAssertThrowsError(try AppStorage.prepare(root: root, legacyModels: legacy, defaults: defaults))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("settings.json")), original)
            XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("weights")), Data([1]))
            XCTAssertEqual(defaults.string(forKey: "hotkey"), "fn")
        }
    }

    func testConflictingModelFoldersAreNotOverwritten() throws {
        try withStorage { root, legacy, defaults in
            defaults.set("fn", forKey: "hotkey")
            try write(Data([1]), to: legacy.appendingPathComponent("weights"))
            try write(Data([2]), to: root.appendingPathComponent("huggingface/weights"))
            XCTAssertThrowsError(try AppStorage.prepare(root: root, legacyModels: legacy, defaults: defaults))
            XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("weights")), Data([1]))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("huggingface/weights")), Data([2]))
            XCTAssertEqual(defaults.string(forKey: "hotkey"), "fn")
        }
    }

    private func withStorage(_ body: (URL, URL, UserDefaults) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "WhisperPTTStorageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: base)
        }
        try body(base.appendingPathComponent("app"), base.appendingPathComponent("old-cache"), defaults)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
