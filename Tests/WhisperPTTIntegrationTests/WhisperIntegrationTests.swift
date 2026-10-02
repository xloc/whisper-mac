import WhisperKit
import WhisperPTTCore
import XCTest

private final class DownloadProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func append(_ fraction: Double) {
        lock.lock()
        values.append(fraction)
        lock.unlock()
    }

    func snapshot() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class WhisperIntegrationTests: XCTestCase {
    func testDownloadReportsProgressAndCompletesMissingFileWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["WHISPER_PTT_RUN_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set WHISPER_PTT_RUN_MODEL_TESTS=1 to run the real download test")
        }
        let manager = FileManager.default
        if !ModelStorage.info("tiny").isDownloaded { _ = try await WhisperModels.download("tiny") }
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let original = ModelStorage.folder("tiny")
        let copy = ModelStorage.folder("tiny", root: root)
        try manager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: original, to: copy)
        let metadata = ".cache/huggingface/download/openai_whisper-tiny"
        let metadataCopy = copy.deletingLastPathComponent().appendingPathComponent(metadata)
        try manager.createDirectory(at: metadataCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: original.deletingLastPathComponent().appendingPathComponent(metadata), to: metadataCopy)
        try await ModelStorage.refresh("tiny", root: root)
        let before = ModelStorage.info("tiny", root: root)
        XCTAssertTrue(before.isDownloaded)
        try manager.removeItem(at: copy.appendingPathComponent("config.json"))
        XCTAssertFalse(ModelStorage.info("tiny", root: root).isDownloaded)

        let progress = DownloadProgress()
        let downloaded = try await WhisperModels.download("tiny", root: root) { progress.append($0) }
        XCTAssertEqual(downloaded.standardizedFileURL.path, copy.standardizedFileURL.path)
        let after = ModelStorage.info("tiny", root: root)
        XCTAssertTrue(after.isDownloaded)
        XCTAssertEqual(after.localBytes, before.localBytes)
        XCTAssertEqual(after.fraction, 1)
        let values = progress.snapshot()
        XCTAssertTrue(values.contains { $0 < 1 }, "No intermediate download progress reported")
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(values.allSatisfy { (0...1).contains($0) })
    }

    func testModelSwitchingPreservesLanguageAcrossRecordingsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["WHISPER_PTT_RUN_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set WHISPER_PTT_RUN_MODEL_TESTS=1 to download/load the base and tiny models")
        }

        for (model, languages) in [("base", ["zh", "en", "zh"]), ("tiny", ["en"]), ("base", ["zh"])] {
            let whisper = try await WhisperModels.load(model)
            XCTAssertEqual(whisper.modelState, .loaded)
            XCTAssertEqual(whisper.modelVariant.description, model)
            let modelFolder = try XCTUnwrap(whisper.modelFolder)
            XCTAssertTrue(modelFolder.path.hasPrefix(ModelStorage.directory.path + "/"))
            XCTAssertEqual(whisper.tokenizerFolder, ModelStorage.directory)

            // Use the app's model loader and transcription path, with a fresh language decision for every recording.
            for language in languages {
                let fixture = try XCTUnwrap(Bundle.module.url(forResource: language, withExtension: "wav", subdirectory: "Fixtures"))
                let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: fixture.path)
                XCTAssertGreaterThan(audio.count, 16_000, "Speech fixture must contain at least one second of audio")
                guard audio.count > 16_000 else { return }
                let text = try await Transcript.transcribe(audio, using: whisper)
                print("\(model), \(language) fixture: \(text)")
                XCTAssertFalse(text.isEmpty)
                let chineseCharacters = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
                if language == "zh" {
                    XCTAssertGreaterThan(chineseCharacters, text.unicodeScalars.count / 2, "Chinese speech became: \(text)")
                } else {
                    XCTAssertEqual(chineseCharacters, 0)
                    XCTAssertTrue(text.lowercased().contains("speech"), "English speech became: \(text)")
                }
            }
            await whisper.unloadModels()
            XCTAssertEqual(whisper.modelState, .unloaded)
        }
    }
}
