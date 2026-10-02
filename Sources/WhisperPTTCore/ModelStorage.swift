import Foundation

public struct ModelCacheInfo: Sendable {
    public let size: Int64?
    public let localBytes: Int64
    public let isDownloaded: Bool

    public var fraction: Double? {
        guard let size, size > 0 else { return nil }
        return min(Double(localBytes) / Double(size), isDownloaded ? 1 : 0.99)
    }
}

public enum ModelStorage {
    public static let directory = AppStorage.directory.appendingPathComponent("huggingface", isDirectory: true)

    private struct File: Decodable {
        let type: String
        let path: String
        let size: Int64
    }

    private static func repository(_ root: URL) -> URL {
        root.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    public static func folder(_ name: String, root: URL = directory) -> URL {
        repository(root).appendingPathComponent("openai_whisper-\(name)", isDirectory: true)
    }

    private static func metadata(_ name: String, root: URL) -> URL {
        repository(root).appendingPathComponent(".cache/huggingface/download/openai_whisper-\(name)", isDirectory: true)
    }

    private static func manifest(_ name: String, root: URL) -> URL {
        root.appendingPathComponent("model-info/\(name).json")
    }

    // Keep the repository's original manifest so sizes remain available offline.
    public static func refresh(_ name: String, root: URL = directory) async throws {
        let url = URL(string: "https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-\(name)?recursive=true")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let files = try JSONDecoder().decode([File].self, from: data).filter { $0.type == "file" }
        guard !files.isEmpty else { throw URLError(.cannotParseResponse) }
        let destination = manifest(name, root: root)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    public static func info(_ name: String, root: URL = directory) -> ModelCacheInfo {
        let manager = FileManager.default
        let local = folder(name, root: root)
        let cache = metadata(name, root: root)
        let bundled = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "ModelInfo")
        let data = (try? Data(contentsOf: manifest(name, root: root))) ?? bundled.flatMap { try? Data(contentsOf: $0) }
        let files = data.flatMap { try? JSONDecoder().decode([File].self, from: $0) }.map { $0.filter { $0.type == "file" } }
        let size = files.map { $0.reduce(Int64(0)) { $0 + $1.size } }
        let downloaded = files.map { files in
            !files.isEmpty && files.allSatisfy { file in
                let url = repository(root).appendingPathComponent(file.path)
                return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == file.size
            }
        } ?? false
        var bytes: Int64 = 0
        for directory in [local, cache] {
            let entries = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            while let url = entries?.nextObject() as? URL {
                guard directory == local || url.pathExtension == "incomplete",
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true else { continue }
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        return ModelCacheInfo(size: size, localBytes: bytes, isDownloaded: downloaded)
    }

    public static func remove(_ name: String, root: URL = directory) throws {
        for url in [folder(name, root: root), metadata(name, root: root)] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
