import AppKit
import WhisperKit

public enum PTTStatus: CaseIterable, Sendable {
    case loading, permissionRequired, ready, recording, transcribing, sent, noSpeech, error

    public var title: String {
        switch self {
        case .loading: "Loading model"
        case .permissionRequired: "Permissions needed"
        case .ready: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .sent: "Text sent"
        case .noSpeech: "No speech detected"
        case .error: "Error"
        }
    }

    public var symbolName: String {
        switch self {
        case .loading: "progress.indicator"
        case .permissionRequired: "waveform.badge.minus"
        case .ready: "mic"
        case .recording: "waveform"
        case .transcribing: "text.viewfinder"
        case .sent: "checkmark.circle"
        case .noSpeech: "waveform.badge.exclamationmark"
        case .error: "xmark.circle"
        }
    }

    public func displayed(microphoneAllowed: Bool, accessibilityAllowed: Bool) -> Self {
        guard self == .ready || self == .permissionRequired else { return self }
        return microphoneAllowed && accessibilityAllowed ? .ready : .permissionRequired
    }
}

public enum WhisperModels {
    public static let choices = ["tiny", "base", "small", "medium", "large-v3", "large-v3_turbo"]

    public static func download(_ name: String, root: URL = ModelStorage.directory, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let folder = try await WhisperKit.download(
            variant: name,
            downloadBase: root,
            progressCallback: { progress?($0.fractionCompleted) }
        )
        try Task.checkCancellation()
        return folder
    }

    public static func load(_ name: String, modelFolder: URL? = nil) async throws -> WhisperKit {
        let folder: URL
        if let modelFolder {
            folder = modelFolder
        } else if ModelStorage.info(name).isDownloaded {
            folder = ModelStorage.folder(name)
        } else {
            folder = try await download(name)
        }
        let whisper = try await WhisperKit(
            modelFolder: folder.path,
            tokenizerFolder: ModelStorage.directory,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            load: true,
            download: false
        )
        guard whisper.modelVariant.isMultilingual else {
            throw WhisperError.decodingFailed("Use a multilingual model such as base, not an English-only .en model.")
        }
        return whisper
    }
}

public enum Hotkey: String, CaseIterable, Sendable {
    case rightOption
    case rightCommand
    case f13
    case fn

    public var title: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .f13: "F13"
        case .fn: "Fn / Globe"
        }
    }

    public var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .f13: 105
        case .fn: 63
        }
    }

    public func state(for event: NSEvent) -> Bool? {
        guard event.keyCode == keyCode else { return nil }
        switch self {
        case .rightOption: return event.modifierFlags.contains(.option)
        case .rightCommand: return event.modifierFlags.contains(.command)
        case .fn: return event.modifierFlags.contains(.function)
        case .f13:
            switch event.type {
            case .keyDown: return true
            case .keyUp: return false
            default: return nil
            }
        }
    }

    public func state(event: Event, flags: NSEvent.ModifierFlags = []) -> Bool? {
        guard event == .flagsChanged || event == .keyDown || event == .keyUp else { return nil }
        switch self {
        case .rightOption: return event == .flagsChanged ? flags.contains(.option) : nil
        case .rightCommand: return event == .flagsChanged ? flags.contains(.command) : nil
        case .fn: return event == .flagsChanged ? flags.contains(.function) : nil
        case .f13:
            switch event {
            case .keyDown: return true
            case .keyUp: return false
            case .flagsChanged: return nil
            case .other: return nil
            }
        }
    }

    public enum Event: Sendable {
        case flagsChanged
        case keyDown
        case keyUp
        case other
    }
}

public enum AudioSamples {
    public static let sampleRate = 16_000.0

    public static func resample(_ input: [Float], from rate: Double) -> [Float] {
        guard rate != sampleRate, !input.isEmpty else { return input }
        let count = Int(Double(input.count) * sampleRate / rate)
        return (0..<count).map { outputIndex in
            let position = Double(outputIndex) * rate / sampleRate
            let lower = min(Int(position), input.count - 1)
            let upper = min(lower + 1, input.count - 1)
            return input[lower] + Float(position - Double(lower)) * (input[upper] - input[lower])
        }
    }
}

public enum Transcript {
    public static func transcribe(_ audio: [Float], using whisper: WhisperKit) async throws -> String {
        let results = try await whisper.transcribe(
            audioArray: audio,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                detectLanguage: true,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )
        )
        return join(results.map(\.text))
    }

    public static func join(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
