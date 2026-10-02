import AppKit
import ApplicationServices
import AVFoundation
import CoreML
import WhisperKit
import WhisperPTTCore

private let sampleRate = AudioSamples.sampleRate

final class Recorder {
    private(set) var engine: AVAudioEngine?
    private let lock = NSLock()
    private var sourceRate = sampleRate
    private var samples = [Float]()

    func start(deviceUID: String?) throws {
        // A fresh engine picks up device and sample-rate changes between recordings.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try AudioInputDevices.select(deviceUID, on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "WhisperPTTAudio", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The selected microphone has no audio input."])
        }
        sourceRate = format.sampleRate
        samples.removeAll(keepingCapacity: true)

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)
            var mono = [Float](repeating: 0, count: frameCount)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount { mono[frame] += channels[channel][frame] }
                mono[frame] /= Float(channelCount)
            }
            self.lock.lock()
            self.samples.append(contentsOf: mono)
            self.lock.unlock()
        }

        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
        } catch {
            engine.stop()
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() -> [Float] {
        guard let engine else { return [] }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        lock.lock()
        let recorded = samples
        lock.unlock()
        return AudioSamples.resample(recorded, from: sourceRate)
    }
}

@MainActor
final class PushToTalk {
    private let recorder = Recorder()
    private var modelName: String
    private var whisper: WhisperKit?
    private var loading = false
    private var recording = false
    private var transcribing = false
    private var monitor: Any?
    private var statusItem: NSStatusItem?
    private let statusSymbol = StatusSymbol()
    private var hotkey: Hotkey
    private var window: PTTWindow?
    private var status: PTTStatus = .loading
    private var statusMessage = "Loading…"
    private var statusReset: Task<Void, Never>?
    private var models: [String: ModelCacheInfo] = [:]
    private var modelErrors: [String: String] = [:]
    private var downloading: String?
    private var downloadFraction: Double?
    private var lastDownloadUpdate = Date.distantPast
    private var refreshingModels = false
    private var history: [HistoryEntry] = []
    private var historyReadable = true
    private var historyError: String?
    private var settings = AppSettings()
    private var startupError: String?
    private var audioInputError: String?
    private var audioInputMonitor: AudioInputMonitor?
    private var audioEngineObserver: NSObjectProtocol?
    private var busy: Bool { loading || recording || transcribing }

    init(modelName: String?) {
        do { settings = try AppStorage.prepare() }
        catch { startupError = "Could not prepare app data: \(error.localizedDescription)" }
        self.modelName = modelName ?? settings.model
        self.hotkey = Hotkey(rawValue: settings.hotkey) ?? .rightOption
    }

    func start() {
        do { history = try TranscriptHistory.load() }
        catch {
            historyReadable = false
            historyError = "Could not load history: \(error.localizedDescription)"
        }
        installStatusItem()
        do {
            audioInputMonitor = try AudioInputMonitor { [weak self] in
                Task { @MainActor in self?.refreshAudioInputs() }
            }
        } catch { startupError = "Could not monitor audio inputs: \(error.localizedDescription)" }
        audioEngineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let engine = notification.object as? AVAudioEngine else { return }
            // Defer teardown until after AVAudioEngine's notification handler returns.
            Task { @MainActor in
                guard let self, self.recording, self.recorder.engine === engine, !engine.isRunning else { return }
                self.recording = false
                _ = self.recorder.stop()
                self.setStatus(.error, "Audio input was interrupted. Please record again.")
            }
        }
        showWindow()
        if let startupError {
            setStatus(.error, startupError)
            return
        }
        refreshModels()
        loadModel()
    }

    private func loadModel() {
        guard !busy, downloading == nil, startupError == nil else { return }
        loading = true
        setStatus(.loading, "Preparing \(modelName)…")
        Task {
            defer {
                loading = false
                updateWindow()
            }
            if let previous = whisper { await previous.unloadModels() }
            whisper = nil
            do {
                let folder: URL
                if ModelStorage.info(modelName).isDownloaded {
                    folder = ModelStorage.folder(modelName)
                } else {
                    setStatus(.loading, "Downloading \(modelName)…")
                    folder = try await downloadModel(modelName)
                }
                setStatus(.loading, "Preparing \(modelName)…")
                whisper = try await WhisperModels.load(modelName, modelFolder: folder)
                modelErrors[modelName] = nil
                settings.model = modelName
                setStatus(.ready, "Ready — hold \(hotkey.title) to speak")
                installHotkey()
                saveSettings()
            } catch {
                modelErrors[modelName] = error.localizedDescription
                setStatus(.error, "Model failed: \(error.localizedDescription)")
            }
        }
    }

    private func saveSettings() {
        do { try AppStorage.saveSettings(settings) }
        catch { setStatus(.error, "Could not save settings: \(error.localizedDescription)") }
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(showWindow)
        if let button = item.button {
            statusSymbol.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(statusSymbol)
            NSLayoutConstraint.activate([
                statusSymbol.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                statusSymbol.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                statusSymbol.widthAnchor.constraint(equalToConstant: 20),
                statusSymbol.heightAnchor.constraint(equalToConstant: 20)
            ])
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(updateWindow), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        statusItem = item
    }

    @objc private func showWindow() {
        if window == nil { createWindow() }
        refreshAudioInputs()
        refreshInventory()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        let newWindow = PTTWindow(modelName: modelName, models: WhisperModels.choices, shortcuts: Hotkey.allCases.map(\.title))
        let actions: [(NSControl, Selector)] = [
            (newWindow.model, #selector(modelChanged(_:))),
            (newWindow.shortcut, #selector(shortcutChanged(_:))),
            (newWindow.audioInput, #selector(audioInputChanged(_:))),
            (newWindow.requestMicrophone, #selector(requestMicrophone)),
            (newWindow.requestAccessibility, #selector(requestAccessibility)),
            (newWindow.microphoneSettings, #selector(openMicrophoneSettings)),
            (newWindow.accessibilitySettings, #selector(openAccessibilitySettings)),
            (newWindow.testPaste, #selector(testPaste)),
            (newWindow.modelList.action, #selector(modelAction(_:))),
            (newWindow.modelList.remove, #selector(removeModel(_:))),
            (newWindow.historyView.openFolder, #selector(openHistory)),
            (newWindow.quit, #selector(quit))
        ]
        for (control, action) in actions {
            control.target = self
            control.action = action
        }
        newWindow.modelList.refresh.target = self
        newWindow.modelList.refresh.action = #selector(refreshModels)
        newWindow.modelList.openFolder.target = self
        newWindow.modelList.openFolder.action = #selector(openModels)
        newWindow.modelList.reveal.target = self
        newWindow.modelList.reveal.action = #selector(revealModel(_:))
        newWindow.onTabChange = { [weak self] in self?.updateModelsWindow() }
        window = newWindow
        newWindow.transcript.string = history.last?.text ?? ""
        updateHistory()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAudioInputs), name: NSApplication.didBecomeActiveNotification, object: NSApp
        )
    }

    @objc private func updateWindow() {
        window?.model.selectItem(withTitle: ModelList.displayName(modelName))
        window?.model.isEnabled = !busy && downloading == nil && startupError == nil
        window?.shortcut.selectItem(at: Hotkey.allCases.firstIndex(of: hotkey) ?? 0)
        window?.shortcut.isEnabled = whisper != nil && !busy
        window?.audioInput.isEnabled = !recording && !transcribing && startupError == nil
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        switch microphone {
        case .authorized: window?.microphone.stringValue = "Allowed"
        case .notDetermined: window?.microphone.stringValue = "Not requested"
        case .denied: window?.microphone.stringValue = "Denied"
        case .restricted: window?.microphone.stringValue = "Restricted"
        @unknown default: window?.microphone.stringValue = "Unknown"
        }
        window?.requestMicrophone.isEnabled = microphone == .notDetermined
        window?.requestMicrophone.isHidden = microphone != .notDetermined
        let trusted = AXIsProcessTrusted()
        window?.accessibility.stringValue = trusted ? "Allowed" : "Required"
        window?.requestAccessibility.isEnabled = !trusted
        window?.requestAccessibility.isHidden = trusted
        window?.testPaste.isEnabled = trusted && !busy
        window?.transcriptPlaceholder.isHidden = !(window?.transcript.string.isEmpty ?? true)

        var displayed = status.displayed(microphoneAllowed: microphone == .authorized, accessibilityAllowed: trusted)
        if displayed == .ready, audioInputError != nil { displayed = .error }
        let message: String
        switch displayed {
        case .permissionRequired: message = "Grant Microphone and Accessibility access to use push-to-talk."
        case .ready: message = "Focus an input, hold \(hotkey.title) to speak, then release."
        case .error where status == .ready: message = audioInputError ?? statusMessage
        default: message = statusMessage
        }
        window?.status.stringValue = displayed.title
        window?.statusDetail.stringValue = message
        window?.statusDetail.toolTip = message
        window?.statusIcon.image = NSImage(systemSymbolName: displayed.symbolName, accessibilityDescription: displayed.title)?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        updateModelsWindow()
        statusSymbol.update(displayed, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        statusItem?.button?.setAccessibilityLabel("Whisper PTT — \(message)")
        statusItem?.button?.toolTip = "Whisper PTT — \(message)"
    }

    @objc private func refreshAudioInputs() {
        do {
            let devices = try AudioInputDevices.available()
            let defaultID = try AudioInputDevices.defaultID()
            do {
                _ = try AudioInputDevices.resolve(settings.inputDeviceUID, devices: devices, defaultID: defaultID)
                audioInputError = nil
            } catch { audioInputError = error.localizedDescription }
            window?.showAudioInputs(devices, defaultID: defaultID,
                                    selectedUID: settings.inputDeviceUID, error: audioInputError)
        } catch {
            audioInputError = "Could not list audio inputs: \(error.localizedDescription)"
            window?.showAudioInputs([], defaultID: nil, selectedUID: settings.inputDeviceUID, error: audioInputError)
        }
        updateWindow()
    }

    @objc private func audioInputChanged(_ sender: NSPopUpButton) {
        guard !recording, !transcribing, startupError == nil else {
            refreshAudioInputs()
            return
        }
        settings.inputDeviceUID = sender.selectedItem?.representedObject as? String
        refreshAudioInputs()
        if !busy, whisper != nil { setStatus(.ready, "Ready") }
        saveSettings()
    }

    private func setStatus(_ status: PTTStatus, _ message: String) {
        statusReset?.cancel()
        self.status = status
        statusMessage = message
        updateWindow()
        print(message)
        if status == .sent || status == .noSpeech {
            statusReset = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.setStatus(.ready, "Ready")
            }
        }
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard !busy, downloading == nil, let selected = sender.selectedItem?.representedObject as? String else {
            updateWindow()
            return
        }
        modelName = selected
        loadModel()
    }

    private func refreshInventory() {
        models = Dictionary(uniqueKeysWithValues: WhisperModels.choices.map { ($0, ModelStorage.info($0)) })
        updateWindow()
    }

    @objc private func refreshModels() {
        guard !refreshingModels else { return }
        refreshingModels = true
        refreshInventory()
        Task {
            var failures = 0
            await withTaskGroup(of: Bool.self) { group in
                for name in WhisperModels.choices {
                    group.addTask {
                        do { try await ModelStorage.refresh(name); return true }
                        catch { return false }
                    }
                }
                for await success in group {
                    if !success { failures += 1 }
                    refreshInventory()
                }
            }
            refreshingModels = false
            window?.modelList.summary.toolTip = failures == 0 ? nil
                : "Could not refresh all sizes. Showing the last saved model information."
            updateWindow()
        }
    }

    private func downloadModel(_ name: String) async throws -> URL {
        downloading = name
        downloadFraction = nil
        lastDownloadUpdate = .distantPast
        modelErrors[name] = nil
        refreshInventory()
        defer {
            downloading = nil
            downloadFraction = nil
            refreshInventory()
        }
        return try await WhisperModels.download(name) { [weak self] fraction in
            Task { @MainActor in
                guard let self, self.downloading == name,
                      fraction == 1 || Date().timeIntervalSince(self.lastDownloadUpdate) >= 0.25 else { return }
                self.lastDownloadUpdate = Date()
                self.downloadFraction = fraction
                self.refreshInventory()
            }
        }
    }

    private func updateModelsWindow() {
        guard let window else { return }
        let canManage = !busy && downloading == nil && startupError == nil
        window.modelList.refresh.isEnabled = !refreshingModels && startupError == nil
        let stored = ByteCountFormatter.string(fromByteCount: models.values.reduce(0) { $0 + $1.localBytes }, countStyle: .file)
        window.modelList.summary.stringValue = refreshingModels ? "Updating model sizes…"
            : "\(models.values.filter(\.isDownloaded).count) downloaded · \(stored) cached"
        window.downloadStatus.isHidden = downloading == nil || window.tabs.selectedTabViewItem?.identifier as? String == "models"
        let fraction = downloading.flatMap { models[$0]?.fraction ?? downloadFraction }
        if let downloading {
            window.downloadStatus.stringValue = "Downloading \(ModelList.displayName(downloading))" + (fraction.map { " — \(Int($0 * 100))%" } ?? "…")
        }
        let rows: [ModelListRow] = WhisperModels.choices.compactMap { name in
            guard let info = models[name] else { return nil }
            let active = isActiveModel(name)
            let preparing = name == modelName && loading && downloading == nil
            let transferring = name == downloading
            let rowFraction = transferring ? fraction : info.fraction
            let state: String
            if preparing { state = "Preparing…" }
            else if transferring { state = rowFraction.map { "Downloading \(Int($0 * 100))%" } ?? "Starting download…" }
            else if modelErrors[name] != nil { state = "Failed — retry" }
            else if active { state = "In use" }
            else if info.isDownloaded { state = "Downloaded" }
            else if info.localBytes > 0 { state = "Partial download" }
            else { state = "Not downloaded" }
            let size = info.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unknown"
            let local = ByteCountFormatter.string(fromByteCount: info.localBytes, countStyle: .file)
            let detail = modelErrors[name] ?? (active ? "Currently used for dictation." : info.isDownloaded
                ? "Downloaded and available offline." : info.localBytes > 0
                ? "\(local) of \(size) cached." : "Download this model to use it for dictation.")
            return ModelListRow(name: name, size: size, status: state, detail: detail,
                actionTitle: active ? "In Use" : modelErrors[name] != nil ? "Retry" : info.isDownloaded ? "Use Model" : "Download",
                canUse: canManage && !active, canRemove: canManage && !active && info.localBytes > 0,
                isCached: info.localBytes > 0)
        }
        window.modelList.show(rows, selecting: modelName)
    }

    private func isActiveModel(_ name: String) -> Bool {
        whisper?.modelFolder?.standardizedFileURL.path == ModelStorage.folder(name).standardizedFileURL.path
    }

    @objc private func modelAction(_ sender: NSButton) {
        guard !busy, downloading == nil else { return }
        let name = WhisperModels.choices[sender.tag]
        if models[name]?.isDownloaded == true {
            modelName = name
            loadModel()
        } else {
            Task {
                guard !busy, downloading == nil else { return }
                do { _ = try await downloadModel(name) }
                catch { modelErrors[name] = error.localizedDescription }
                refreshInventory()
            }
        }
    }

    @objc private func removeModel(_ sender: NSButton) {
        guard !busy, downloading == nil else { return }
        let name = WhisperModels.choices[sender.tag]
        guard !isActiveModel(name) else { return }
        do {
            try ModelStorage.remove(name)
            modelErrors[name] = nil
        } catch { modelErrors[name] = error.localizedDescription }
        refreshInventory()
    }

    @objc private func revealModel(_ sender: NSMenuItem) {
        let folder = ModelStorage.folder(WhisperModels.choices[sender.tag])
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    @objc private func openModels() {
        do {
            try FileManager.default.createDirectory(at: ModelStorage.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(ModelStorage.directory)
        } catch { window?.modelList.summary.stringValue = error.localizedDescription }
    }

    private func updateHistory() {
        guard let view = window?.historyView else { return }
        let date = DateFormatter()
        date.dateStyle = .medium
        date.timeStyle = .short
        view.show(history.map { (date: date.string(from: $0.date), text: $0.text) }, error: historyError)
        view.info.toolTip = historyError ?? TranscriptHistory.fileURL.path
        view.openFolder.toolTip = AppStorage.directory.path
    }

    @objc private func openHistory() {
        let folder = AppStorage.directory
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.open(folder)
        } catch { setStatus(.error, "Could not open app folder: \(error.localizedDescription)") }
    }

    @objc private func shortcutChanged(_ sender: NSPopUpButton) {
        guard !busy else {
            updateWindow()
            return
        }
        hotkey = Hotkey.allCases[sender.indexOfSelectedItem]
        settings.hotkey = hotkey.rawValue
        setStatus(whisper == nil ? .error : .ready, whisper == nil ? "Choose a model to load." : "Ready")
        installHotkey()
        saveSettings()
    }

    @objc private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.updateWindow() }
        }
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateWindow()
    }

    @objc private func openMicrophoneSettings() {
        openPrivacySettings("Privacy_Microphone")
    }

    @objc private func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    private func openPrivacySettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        if !NSWorkspace.shared.open(url) {
            setStatus(.error, "Could not open System Settings → Privacy & Security")
        }
    }

    @objc private func testPaste() {
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            return
        }
        transcribing = true
        window?.orderOut(nil)
        setStatus(.transcribing, "Paste test in 0.5 seconds…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.paste("Whisper PTT paste test")
            self.transcribing = false
            self.updateWindow()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func installHotkey() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        let selectedHotkey = hotkey
        monitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            guard let self, let pressed = selectedHotkey.state(for: event) else { return }
            Task { @MainActor in
                if pressed { self.beginRecording() }
                else { self.finishRecording() }
            }
        }
    }

    private func beginRecording() {
        guard !busy, whisper != nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, AXIsProcessTrusted() else {
            setStatus(.permissionRequired, "Grant Microphone and Accessibility access.")
            return
        }
        refreshAudioInputs()
        guard audioInputError == nil else {
            setStatus(.ready, "Ready")
            return
        }
        do {
            try recorder.start(deviceUID: settings.inputDeviceUID)
            recording = true
            print("recording…")
            setStatus(.recording, "Recording… release \(hotkey.title) to transcribe")
        } catch {
            fputs("failed to start microphone: \(error)\n", stderr)
            setStatus(.error, "Microphone failed to start: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard recording else { return }
        let uninterrupted = recorder.engine?.isRunning == true
        recording = false
        let audio = recorder.stop()
        guard uninterrupted else {
            setStatus(.error, "Audio input was interrupted. Please record again.")
            return
        }
        guard audio.count > Int(sampleRate * 0.05), let whisper else {
            setStatus(.noSpeech, "Recording was too short")
            return
        }
        transcribing = true
        setStatus(.transcribing, "Transcribing…")

        Task {
            defer {
                transcribing = false
                updateWindow()
            }
            do {
                let text = try await Transcript.transcribe(audio, using: whisper)
                guard !text.isEmpty else {
                    setStatus(.noSpeech, "No speech detected")
                    return
                }
                print(text)
                window?.transcript.string = text
                history.append(HistoryEntry(text: text, model: modelName))
                if historyReadable {
                    do {
                        try TranscriptHistory.save(history)
                        historyError = nil
                    } catch { historyError = error.localizedDescription }
                }
                updateHistory()
                paste(text)
                if let historyError {
                    setStatus(.error, "\(statusMessage) · History was not saved: \(historyError)")
                }
            } catch {
                let message = error.localizedDescription
                fputs("transcription failed: \(message)\n", stderr)
                setStatus(.error, "Transcription failed: \(message)")
            }
        }
    }

    private func paste(_ text: String) {
        guard AXIsProcessTrusted() else {
            setStatus(.permissionRequired, "Paste skipped: grant Accessibility access")
            updateWindow()
            return
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            setStatus(.error, "Pasteboard write failed")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        guard let down, let up else {
            setStatus(.error, "Could not create paste event")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        setStatus(.sent, "Text sent to the current app")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pasteboard.string(forType: .string) == text else { return }
            pasteboard.clearContents()
            if let previous { pasteboard.setString(previous, forType: .string) }
        }
    }
}

struct Arguments {
    var model: String?

    init() {
        var values = CommandLine.arguments.dropFirst()
        while let value = values.popFirst() {
            switch value {
            case "--model": model = values.popFirst() ?? model
            case "--help":
                print("usage: whisper-ptt [--model MODEL]")
                exit(0)
            default: break
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let arguments = Arguments()
let controller = MainActor.assumeIsolated {
    PushToTalk(modelName: arguments.model)
}
Task { @MainActor in controller.start() }
app.run()
