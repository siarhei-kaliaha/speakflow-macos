import AppKit
import Foundation

final class ControlCenterHistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onClearHistory: (() -> Void)?

    private let historyTable = NSTableView()
    private let copySelectedButton = NSButton()
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "Your recent dictation snippets will appear here. Hold the global key and speak to create the first one.")
    private var captures: [CaptureRecord] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(captures: [CaptureRecord]) {
        self.captures = captures.filter { $0.kind == .dictationSnippet }
        historyTable.reloadData()
        emptyStateLabel.isHidden = !self.captures.isEmpty
        copySelectedButton.isEnabled = historyTable.selectedRow >= 0
    }

    private func setupUI() {
        let container = controlCenterPanelView(cornerRadius: 8)
        addSubview(container)

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let headerTitle = controlCenterSectionTitle("Dictation Snippets")
        let headerSubtitle = NSTextField(labelWithString: "Fast hold-to-talk captures, polished and ready to reuse.")
        headerSubtitle.translatesAutoresizingMaskIntoConstraints = false
        headerSubtitle.font = .systemFont(ofSize: 13)
        headerSubtitle.textColor = ControlCenterChrome.bodyColor
        header.addSubview(headerTitle)
        header.addSubview(headerSubtitle)

        let headerDivider = dividerView()
        container.addSubview(headerDivider)

        let tableScrollView = NSScrollView()
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        tableScrollView.drawsBackground = false
        tableScrollView.borderType = .noBorder
        tableScrollView.hasVerticalScroller = true
        container.addSubview(tableScrollView)

        historyTable.translatesAutoresizingMaskIntoConstraints = false
        historyTable.headerView = nil
        historyTable.rowHeight = 62
        historyTable.intercellSpacing = .zero
        historyTable.selectionHighlightStyle = .regular
        historyTable.backgroundColor = .clear
        historyTable.delegate = self
        historyTable.dataSource = self
        historyTable.target = self
        historyTable.doubleAction = #selector(copySelectedHistory)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.resizingMask = .autoresizingMask
        historyTable.addTableColumn(column)
        tableScrollView.documentView = historyTable

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 13)
        emptyStateLabel.textColor = ControlCenterChrome.secondaryColor
        emptyStateLabel.maximumNumberOfLines = 0
        tableScrollView.addSubview(emptyStateLabel)

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.layer?.backgroundColor = ControlCenterChrome.surfaceBackground.cgColor
        container.addSubview(footer)

        let footerDivider = dividerView()
        container.addSubview(footerDivider)

        copySelectedButton.title = "Copy Selected"
        copySelectedButton.target = self
        copySelectedButton.action = #selector(copySelectedHistory)
        copySelectedButton.isEnabled = false
        controlCenterStyleButton(copySelectedButton, style: .primary)

        let clearButton = NSButton(title: "Clear Snippets", target: self, action: #selector(clearHistoryTapped))
        controlCenterStyleButton(clearButton, style: .secondary)

        let footerButtons = NSStackView(views: [copySelectedButton, clearButton])
        footerButtons.translatesAutoresizingMaskIntoConstraints = false
        footerButtons.orientation = .horizontal
        footerButtons.alignment = .centerY
        footerButtons.spacing = 12
        footer.addSubview(footerButtons)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 520),

            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 88),

            headerTitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            headerTitle.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            headerTitle.topAnchor.constraint(equalTo: header.topAnchor, constant: 20),

            headerSubtitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            headerSubtitle.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            headerSubtitle.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 4),

            headerDivider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerDivider.topAnchor.constraint(equalTo: header.bottomAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 64),

            footerDivider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footerDivider.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footerDivider.heightAnchor.constraint(equalToConstant: 1),

            tableScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: footerDivider.topAnchor),
            tableScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),

            emptyStateLabel.leadingAnchor.constraint(equalTo: tableScrollView.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(equalTo: tableScrollView.trailingAnchor, constant: -24),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableScrollView.centerYAnchor),

            footerButtons.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            footerButtons.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    private func dividerView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = ControlCenterChrome.borderLight.cgColor
        return view
    }

    @objc
    private func clearHistoryTapped() {
        onClearHistory?()
    }

    @objc
    private func copySelectedHistory() {
        let row = historyTable.selectedRow
        guard captures.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(captures[row].finalText, forType: .string)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        captures.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        copySelectedButton.isEnabled = historyTable.selectedRow >= 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard captures.indices.contains(row) else { return nil }

        let entry = captures[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.clear.cgColor

        let titleTag = 101
        let subtitleTag = 102
        let titleField: NSTextField
        let subtitleField: NSTextField
        let divider: NSView

        if let existingTitle = cell.viewWithTag(titleTag) as? NSTextField,
           let existingSubtitle = cell.viewWithTag(subtitleTag) as? NSTextField,
           let existingDivider = cell.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("HistoryCellDivider") }) {
            titleField = existingTitle
            subtitleField = existingSubtitle
            divider = existingDivider
        } else {
            let title = NSTextField(labelWithString: "")
            title.translatesAutoresizingMaskIntoConstraints = false
            title.tag = titleTag
            title.font = .systemFont(ofSize: 14, weight: .medium)
            title.textColor = ControlCenterChrome.titleColor
            title.lineBreakMode = .byTruncatingTail

            let subtitle = NSTextField(labelWithString: "")
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            subtitle.tag = subtitleTag
            subtitle.font = .systemFont(ofSize: 12)
            subtitle.textColor = ControlCenterChrome.secondaryColor
            subtitle.lineBreakMode = .byTruncatingTail

            let separator = dividerView()
            separator.identifier = NSUserInterfaceItemIdentifier("HistoryCellDivider")

            cell.addSubview(title)
            cell.addSubview(subtitle)
            cell.addSubview(separator)

            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -24),
                title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 14),

                subtitle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
                subtitle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -24),
                subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

                separator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
                separator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -24),
                separator.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1)
            ])

            titleField = title
            subtitleField = subtitle
            divider = separator
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        titleField.stringValue = entry.finalText
        subtitleField.stringValue = "\(formatter.string(from: entry.createdAt)) · \(entry.provider)"
        divider.isHidden = row == captures.count - 1

        return cell
    }
}
