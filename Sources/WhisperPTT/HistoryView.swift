import AppKit

@MainActor
final class HistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSUserInterfaceValidations {
    let table = NSTableView()
    let search = NSSearchField()
    let placeholder = NSTextField(labelWithString: "Transcripts will be saved here across app launches.")
    let info = NSTextField(labelWithString: "No transcripts yet")
    let openFolder = NSButton(title: "Open App Folder…", target: nil, action: nil)
    let copyText = NSButton(title: "Copy Text", target: nil, action: nil)
    let preview = NSTextView()
    let previewTitle = NSTextField(labelWithString: "Select a transcript to preview")
    private var entries: [(date: String, text: String)] = []
    private var visibleRows: [Int] = []
    private var error: String?

    var selectedText: String {
        table.selectedRowIndexes.map { entries[visibleRows[$0]].text }.joined(separator: "\n\n")
    }

    init() {
        super.init(frame: .zero)
        search.placeholderString = "Search transcripts"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(filter(_:))
        table.style = .inset
        table.autoresizingMask = [.width]
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 32
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("date", "Time", 180.0), ("text", "Transcript", 350.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "date" ? 150 : 200
            column.resizingMask = id == "text" ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.textColor = .secondaryLabelColor
        scroll.contentView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: scroll.contentView.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: scroll.contentView.centerYAnchor)
        ])
        preview.isEditable = false
        preview.isRichText = false
        preview.font = .systemFont(ofSize: NSFont.systemFontSize)
        preview.textContainerInset = NSSize(width: 8, height: 8)
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        let previewScroll = NSScrollView()
        previewScroll.hasVerticalScroller = true
        previewScroll.autohidesScrollers = true
        previewScroll.borderType = .bezelBorder
        previewScroll.documentView = preview
        let previewSection = NSStackView(views: [previewTitle, previewScroll])
        previewSection.orientation = .vertical
        previewSection.alignment = .leading
        previewSection.spacing = 4
        previewScroll.widthAnchor.constraint(equalTo: previewSection.widthAnchor).isActive = true
        copyText.target = self
        copyText.action = #selector(copy(_:))
        copyText.isEnabled = false
        copyText.controlSize = .small
        openFolder.controlSize = .small
        info.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        info.textColor = .secondaryLabelColor
        info.lineBreakMode = .byTruncatingTail
        info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [info, NSView(), copyText, openFolder])
        footer.distribution = .fill
        footer.alignment = .centerY
        footer.spacing = 12
        let stack = NSStackView(views: [search, scroll, previewSection, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            previewScroll.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ entries: [(date: String, text: String)], error: String?) {
        self.entries = entries
        self.error = error
        applyFilter()
    }

    @objc private func filter(_ sender: Any?) { applyFilter() }

    private func applyFilter() {
        let selection = Set(table.selectedRowIndexes.map { visibleRows[$0] })
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleRows = entries.indices.reversed().filter {
            query.isEmpty || entries[$0].text.localizedCaseInsensitiveContains(query)
        }
        table.reloadData()
        var selected = IndexSet(visibleRows.indices.filter { selection.contains(visibleRows[$0]) })
        if selected.isEmpty, !visibleRows.isEmpty { selected.insert(0) }
        table.selectRowIndexes(selected, byExtendingSelection: false)
        updateSelection()
        placeholder.isHidden = !visibleRows.isEmpty
        placeholder.stringValue = entries.isEmpty ? (error == nil
            ? "Transcripts will be saved here across app launches." : "History could not be loaded.") : "No matching transcripts."
        let count = query.isEmpty ? "\(entries.count) transcripts" : "\(visibleRows.count) of \(entries.count) transcripts"
        info.stringValue = error == nil ? count : "\(count) · History not saved"
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let entry = entries[visibleRows[row]]
        let isTranscript = column.identifier.rawValue == "text"
        let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = column.identifier
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = isTranscript ? entry.text.split(whereSeparator: \.isNewline).joined(separator: " ") : entry.date
        cell.toolTip = isTranscript ? entry.text : entry.date
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelection()
    }

    private func updateSelection() {
        copyText.isEnabled = !table.selectedRowIndexes.isEmpty
        let count = table.selectedRowIndexes.count
        previewTitle.stringValue = count == 0 ? "Select a transcript to preview" : count == 1 ? "Preview" : "\(count) selected transcripts"
        let text = selectedText
        if preview.string != text {
            preview.string = text
            preview.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    @objc func copy(_ sender: Any?) {
        guard !table.selectedRowIndexes.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    @objc func find(_ sender: Any?) { window?.makeFirstResponder(search) }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        window != nil && !isHiddenOrHasHiddenAncestor
            && (item.action != #selector(copy(_:)) || !table.selectedRowIndexes.isEmpty)
    }
}
