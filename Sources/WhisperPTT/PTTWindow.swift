import AppKit
import WhisperPTTCore

@MainActor
final class PTTWindow: NSWindow, NSTabViewDelegate {
    let status = NSTextField(wrappingLabelWithString: "Loading…")
    let statusDetail = NSTextField(wrappingLabelWithString: "")
    let statusIcon = NSImageView()
    let downloadStatus = NSTextField(labelWithString: "")
    let tabs = NSTabView()
    let modelList = ModelList()
    let historyView = HistoryView()
    var onTabChange: (() -> Void)?
    let model = NSPopUpButton(frame: .zero, pullsDown: false)
    let shortcut = NSPopUpButton(frame: .zero, pullsDown: false)
    let audioInput = NSPopUpButton(frame: .zero, pullsDown: false)
    let microphone = NSTextField(labelWithString: "Checking…")
    let accessibility = NSTextField(labelWithString: "Checking…")
    let requestMicrophone = NSButton(title: "Allow…", target: nil, action: nil)
    let requestAccessibility = NSButton(title: "Allow…", target: nil, action: nil)
    let microphoneSettings = NSButton(title: "Open Settings…", target: nil, action: nil)
    let accessibilitySettings = NSButton(title: "Open Settings…", target: nil, action: nil)
    let testPaste = NSButton(title: "Test Paste", target: nil, action: nil)
    let quit = NSButton(title: "Quit", target: nil, action: nil)
    let transcript = NSTextView()
    let transcriptPlaceholder = NSTextField(labelWithString: "Your last transcript will appear here.")

    init(modelName: String, models: [String], shortcuts: [String]) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Whisper PTT"
        isReleasedWhenClosed = false
        contentMinSize = NSSize(width: 640, height: 620)
        for name in models.contains(modelName) ? models : models + [modelName] {
            model.addItem(withTitle: ModelList.displayName(name))
            model.lastItem?.representedObject = name
        }
        model.selectItem(withTitle: ModelList.displayName(modelName))
        shortcut.addItems(withTitles: shortcuts)
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        status.font = .systemFont(ofSize: 16, weight: .semibold)
        statusDetail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.maximumNumberOfLines = 3
        let statusText = NSStackView(views: [status, statusDetail])
        statusText.orientation = .vertical
        statusText.alignment = .leading
        statusText.spacing = 4
        for view in statusText.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: statusText.widthAnchor).isActive = true
        }
        statusIcon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let header = NSStackView(views: [statusIcon, statusText])
        header.distribution = .fill
        header.alignment = .centerY
        header.spacing = 12
        header.setContentHuggingPriority(.required, for: .vertical)
        downloadStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        downloadStatus.textColor = .secondaryLabelColor
        downloadStatus.isHidden = true

        let settings = form([
            [NSTextField(labelWithString: "Shortcut"), shortcut],
            [NSTextField(labelWithString: "Audio Input"), audioInput],
            [NSTextField(labelWithString: "Model"), model]
        ])
        for row in 0..<settings.numberOfRows {
            settings.cell(atColumnIndex: 1, rowIndex: row).xPlacement = .leading
        }
        audioInput.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        audioInput.menu?.autoenablesItems = false
        audioInput.toolTip = "System Default follows your Mac's input setting. Selecting a device applies only to Whisper PTT."
        let permissions = form([
            [NSTextField(labelWithString: "Microphone"), microphone, requestMicrophone, microphoneSettings],
            [NSTextField(labelWithString: "Accessibility"), accessibility, requestAccessibility, accessibilitySettings]
        ])
        permissions.column(at: 2).width = requestMicrophone.intrinsicContentSize.width
        for button in [microphoneSettings, accessibilitySettings] {
            button.bezelStyle = .rounded
            button.isBordered = true
        }
        permissions.column(at: 3).width = microphoneSettings.intrinsicContentSize.width
        microphone.toolTip = "Microphone access lets the app record while you hold the shortcut."
        accessibility.toolTip = "Accessibility access lets the app monitor the shortcut and paste text."

        transcript.isEditable = false
        transcript.isRichText = false
        transcript.drawsBackground = false
        transcript.font = .systemFont(ofSize: NSFont.systemFontSize)
        transcript.isVerticallyResizable = true
        transcript.isHorizontallyResizable = false
        transcript.autoresizingMask = [.width]
        transcript.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = transcript
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true

        let transcriptContent = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        transcriptPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        transcriptPlaceholder.textColor = .secondaryLabelColor
        transcriptContent.addSubview(scroll)
        transcriptContent.addSubview(transcriptPlaceholder)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: transcriptContent.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: transcriptContent.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: transcriptContent.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: transcriptContent.bottomAnchor),
            transcriptPlaceholder.centerXAnchor.constraint(equalTo: transcriptContent.centerXAnchor),
            transcriptPlaceholder.centerYAnchor.constraint(equalTo: transcriptContent.centerYAnchor)
        ])
        let transcriptSection = section("Last transcript", transcriptContent)
        transcriptSection.setContentHuggingPriority(.init(1), for: .vertical)
        let dictation = NSStackView(views: [
            section("Push to talk", settings), section("Permissions", permissions), transcriptSection
        ])
        dictation.orientation = .vertical
        dictation.alignment = .leading
        dictation.spacing = 24
        for view in dictation.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: dictation.widthAnchor).isActive = true
        }
        let dictationPage = NSView()
        embed(dictation, in: dictationPage)
        let dictationTab = NSTabViewItem(identifier: "dictation")
        dictationTab.label = "Dictation"
        dictationTab.view = dictationPage
        tabs.addTabViewItem(dictationTab)

        let modelsPage = NSView()
        embed(modelList, in: modelsPage)
        let modelsTab = NSTabViewItem(identifier: "models")
        modelsTab.label = "Models"
        modelsTab.view = modelsPage
        tabs.addTabViewItem(modelsTab)

        let historyPage = NSView()
        embed(historyView, in: historyPage)
        let historyTab = NSTabViewItem(identifier: "history")
        historyTab.label = "History"
        historyTab.view = historyPage
        tabs.addTabViewItem(historyTab)
        tabs.delegate = self
        tabs.setContentHuggingPriority(.init(1), for: .vertical)

        testPaste.controlSize = .small
        testPaste.toolTip = "Hide this window and paste a sample into the previously focused app."
        quit.controlSize = .small
        let footer = NSStackView(views: [testPaste, NSView(), quit])
        footer.orientation = .horizontal
        footer.distribution = .fill
        footer.alignment = .centerY
        footer.heightAnchor.constraint(equalToConstant: quit.intrinsicContentSize.height).isActive = true
        let stack = NSStackView(views: [header, downloadStatus, tabs, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 16
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        contentView = content
        let appMenu = NSMenu(title: "Whisper PTT")
        appMenu.addItem(withTitle: "Quit Whisper PTT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(HistoryView.find(_:)), keyEquivalent: "f").target = historyView
        let menu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        NSApp.mainMenu = menu
        center()
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        testPaste.isHidden = tabViewItem?.identifier as? String != "dictation"
        onTabChange?()
    }

    func showAudioInputs(_ devices: [AudioInputDevice], defaultID: UInt32?, selectedUID: String?, error: String?) {
        audioInput.removeAllItems()
        let defaultName = devices.first { $0.id == defaultID }?.name
        audioInput.addItem(withTitle: defaultName.map { "System Default — \($0)" } ?? "System Default")
        audioInput.lastItem?.toolTip = error ?? "Use your Mac's current default microphone."
        for device in devices {
            audioInput.addItem(withTitle: device.name)
            audioInput.lastItem?.representedObject = device.uid
        }
        if let selectedUID {
            if let item = audioInput.itemArray.first(where: { $0.representedObject as? String == selectedUID }) {
                audioInput.select(item)
            } else {
                audioInput.addItem(withTitle: "Selected microphone unavailable")
                audioInput.lastItem?.representedObject = selectedUID
                audioInput.lastItem?.isEnabled = false
                audioInput.lastItem?.toolTip = "Reconnect your microphone or choose another audio input."
                audioInput.selectItem(at: audioInput.numberOfItems - 1)
            }
        }
    }

    private func embed(_ view: NSView, in content: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func form(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.rowAlignment = .firstBaseline
        grid.xPlacement = .fill
        grid.column(at: 0).width = 90
        grid.column(at: 0).xPlacement = .leading
        return grid
    }

    private func section(_ title: String, _ view: NSView) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let stack = NSStackView(views: [heading, view])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
}
