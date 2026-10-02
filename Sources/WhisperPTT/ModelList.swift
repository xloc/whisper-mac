import AppKit

struct ModelListRow {
    let name: String
    let size: String
    let status: String
    let detail: String
    let actionTitle: String
    let canUse: Bool
    let canRemove: Bool
    let isCached: Bool
}

@MainActor
final class ModelList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let action = NSButton(title: "Download", target: nil, action: nil)
    let remove = NSButton(title: "Remove Download", target: nil, action: nil)
    let reveal = NSMenuItem(title: "Show Selected Model in Finder", action: nil, keyEquivalent: "")
    let refresh = NSMenuItem(title: "Refresh Model Sizes", action: nil, keyEquivalent: "")
    let openFolder = NSMenuItem(title: "Open Model Folder…", action: nil, keyEquivalent: "")
    let summary = NSTextField(labelWithString: "Checking models…")
    let selectedTitle = NSTextField(labelWithString: "Select a model")
    let selectedDetail = NSTextField(wrappingLabelWithString: "")
    private(set) var rows: [ModelListRow] = []

    init() {
        super.init(frame: .zero)
        table.style = .inset
        table.autoresizingMask = [.width]
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 32
        table.allowsEmptySelection = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        for (id, title, width) in [("name", "Model", 230.0), ("size", "Size", 90.0), ("status", "Status", 150.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "name" ? 140 : width
            column.resizingMask = id == "name" ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true

        selectedTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        selectedDetail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        selectedDetail.textColor = .secondaryLabelColor
        selectedDetail.maximumNumberOfLines = 3
        let selection = NSStackView(views: [selectedTitle, selectedDetail])
        selection.orientation = .vertical
        selection.alignment = .leading
        selection.spacing = 4
        for view in selection.arrangedSubviews { view.widthAnchor.constraint(equalTo: selection.widthAnchor).isActive = true }
        let controls = NSStackView(views: [selection, action, remove])
        controls.distribution = .fill
        controls.alignment = .centerY
        controls.spacing = 12
        controls.detachesHiddenViews = false
        action.widthAnchor.constraint(equalToConstant: 100).isActive = true
        remove.widthAnchor.constraint(equalToConstant: remove.intrinsicContentSize.width).isActive = true

        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.textColor = .secondaryLabelColor
        let more = NSPopUpButton(frame: .zero, pullsDown: true)
        more.controlSize = .small
        more.addItem(withTitle: "More")
        more.menu?.autoenablesItems = false
        more.menu?.addItem(reveal)
        more.menu?.addItem(.separator())
        more.menu?.addItem(refresh)
        more.menu?.addItem(openFolder)
        let footer = NSStackView(views: [summary, NSView(), more])
        footer.distribution = .fill
        footer.alignment = .centerY
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        let stack = NSStackView(views: [scroll, controls, spacer, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        for view in [scroll, controls, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    func show(_ rows: [ModelListRow], selecting name: String) {
        let previous = table.selectedRow
        self.rows = rows
        table.reloadData()
        if !rows.isEmpty {
            let selected = rows.indices.contains(previous) ? previous : rows.firstIndex { $0.name == name } ?? 0
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        }
        updateSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let item = rows[row]
        let text: String
        switch tableColumn.identifier.rawValue {
        case "name": text = Self.displayName(item.name)
        case "size": text = item.size
        default: text = item.status
        }
        let id = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = text
        cell.toolTip = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }

    private func updateSelection() {
        let index = table.selectedRow
        guard rows.indices.contains(index) else {
            action.isEnabled = false
            remove.isEnabled = false
            reveal.isEnabled = false
            return
        }
        let row = rows[index]
        selectedTitle.stringValue = Self.displayName(row.name)
        selectedDetail.stringValue = row.detail
        selectedDetail.toolTip = row.detail
        action.title = row.actionTitle
        action.isEnabled = row.canUse
        action.tag = index
        remove.isHidden = !row.isCached
        remove.isEnabled = row.canRemove
        remove.tag = index
        reveal.isEnabled = row.isCached
        reveal.tag = index
    }
}
