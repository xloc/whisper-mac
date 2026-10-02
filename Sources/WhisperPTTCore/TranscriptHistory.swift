import Foundation

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let date: Date
    public let model: String
    public let text: String

    public init(text: String, model: String, date: Date = Date()) {
        self.date = date
        self.model = model
        self.text = text
    }
}

public enum TranscriptHistory {
    public static let fileURL = AppStorage.directory.appendingPathComponent("history.json")

    public static func load(from url: URL = fileURL) throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryEntry].self, from: Data(contentsOf: url))
    }

    public static func save(_ entries: [HistoryEntry], to url: URL = fileURL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
    }
}
