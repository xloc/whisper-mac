import XCTest
@testable import WhisperPTTCore

final class ModelStorageTests: XCTestCase {
    func testPartialDownloadsAndTruncatedFilesAreNotComplete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ModelStorage.folder("base", root: root)
        let metadata = model.deletingLastPathComponent().appendingPathComponent(".cache/huggingface/download/openai_whisper-base")
        let manifest = """
        [{"type":"file","path":"openai_whisper-base/graph","size":4},
         {"type":"file","path":"openai_whisper-base/weights","size":6}]
        """
        try write(Data(manifest.utf8), to: root.appendingPathComponent("model-info/base.json"))
        XCTAssertEqual(ModelStorage.info("base", root: root).size, 10)
        XCTAssertEqual(ModelStorage.info("base", root: root).localBytes, 0)
        XCTAssertFalse(ModelStorage.info("base", root: root).isDownloaded)

        try write(Data(repeating: 1, count: 4), to: model.appendingPathComponent("graph"))
        try write(Data(repeating: 1, count: 3), to: metadata.appendingPathComponent("weights.etag.incomplete"))
        try write(Data("completion metadata".utf8), to: metadata.appendingPathComponent("graph.metadata"))
        let partial = ModelStorage.info("base", root: root)
        XCTAssertFalse(partial.isDownloaded)
        XCTAssertEqual(partial.localBytes, 7, "Completion metadata should not count as downloaded model bytes")
        XCTAssertEqual(try XCTUnwrap(partial.fraction), 0.7, accuracy: 0.001)

        try FileManager.default.removeItem(at: metadata.appendingPathComponent("weights.etag.incomplete"))
        try write(Data(repeating: 1, count: 5), to: model.appendingPathComponent("weights"))
        XCTAssertFalse(ModelStorage.info("base", root: root).isDownloaded, "A truncated weight file must not show as downloaded")
        try write(Data(repeating: 1, count: 6), to: model.appendingPathComponent("weights"))
        let complete = ModelStorage.info("base", root: root)
        XCTAssertTrue(complete.isDownloaded)
        XCTAssertEqual(complete.localBytes, 10)
        XCTAssertEqual(complete.fraction, 1)

        try write(Data([1]), to: root.appendingPathComponent("models/shared-tokenizer/tokenizer.json"))
        try ModelStorage.remove("base", root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path))
        XCTAssertEqual(ModelStorage.info("base", root: root).localBytes, 0)
        XCTAssertFalse(ModelStorage.info("base", root: root).isDownloaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("models/shared-tokenizer/tokenizer.json").path))
    }

    func testBundledSizesAreAvailableBeforeAnyNetworkRequest() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in WhisperModels.choices {
            let info = ModelStorage.info(name, root: root)
            XCTAssertGreaterThan(info.size ?? 0, 70_000_000)
            XCTAssertEqual(info.localBytes, 0)
            XCTAssertFalse(info.isDownloaded)
            XCTAssertEqual(info.fraction, 0)
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
