import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var model: String
    public var hotkey: String

    public init(model: String = "base", hotkey: String = "rightOption") {
        self.model = model
        self.hotkey = hotkey
    }
}

public enum AppStorage {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".whisper-ptt", isDirectory: true)
    public static let legacyModelDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Whisper PTT/huggingface", isDirectory: true)

    public static func prepare(root: URL = directory, legacyModels: URL = legacyModelDirectory,
                               defaults: UserDefaults = .standard) throws -> AppSettings {
        let manager = FileManager.default
        let file = root.appendingPathComponent("settings.json")
        var settings = AppSettings()
        if manager.fileExists(atPath: file.path) {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: file))
        } else {
            settings.model = defaults.string(forKey: "model") ?? settings.model
            settings.hotkey = defaults.string(forKey: "hotkey") ?? settings.hotkey
            try saveSettings(settings, root: root)
        }
        if manager.fileExists(atPath: legacyModels.path) {
            // Rename the entire cache, including tokenizers and partial downloads.
            try manager.moveItem(at: legacyModels, to: root.appendingPathComponent("huggingface", isDirectory: true))
        }
        // Remove the old values so deleting the app folder really resets preferences.
        defaults.removeObject(forKey: "model")
        defaults.removeObject(forKey: "hotkey")
        return settings
    }

    public static func saveSettings(_ settings: AppSettings, root: URL = directory) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: root.appendingPathComponent("settings.json"), options: .atomic)
    }
}
