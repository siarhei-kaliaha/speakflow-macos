import AppKit
import Foundation

final class ControlCenterHistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onClearHistory: (() -> Void)?

    private let historyTable = NSTableView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "Dictation history will appear here once you start speaking.")
    private var history: [HistoryEntry] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(history: [HistoryEntry]) {
        self.history = history
        historyTable.reloadData()
        emptyHistoryLabel.isHidden = !history.isEmpty
    }

    private func setupUI() {
        let card = controlCenterCardView()
        addSubview(card)

        let historyStack = NSStackView()
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 16

        let historyHeader = NSStackView()
        historyHeader.translatesAutoresizingMaskIntoConstraints = false
        historyHeader.orientation = .horizontal
        historyHeader.alignment = .centerY
        historyHeader.spacing = 10

        let historyTitle = controlCenterSectionTitle("Recent Dictations")
        let historySubtitle = NSTextField(labelWithString: "Latest voice outputs, ready to copy or review.")
        historySubtitle.font = .systemFont(ofSize: 13)
        historySubtitle.textColor = .secondaryLabelColor
        let historyHeaderText = NSStackView()
        historyHeaderText.translatesAutoresizingMaskIntoConstraints = false
        historyHeaderText.orientation = .vertical
        historyHeaderText.alignment = .leading
        historyHeaderText.spacing = 2
        historyHeaderText.addArrangedSubview(historyTitle)
        historyHeaderText.addArrangedSubview(historySubtitle)
        historyHeader.addArrangedSubview(historyHeaderText)
        historyHeader.addArrangedSubview(NSView())

        let historyScroll = NSScrollView()
        historyScroll.translatesAutoresizingMaskIntoConstraints = false
        historyScroll.hasVerticalScroller = true
        historyScroll.borderType = .noBorder
        historyScroll.drawsBackground = false
        historyTable.headerView = nil
        historyTable.rowHeight = 58
        historyTable.intercellSpacing = NSSize(width: 0, height: 8)
        historyTable.selectionHighlightStyle = .regular
        historyTable.delegate = self
        historyTable.dataSource = self
        historyTable.backgroundColor = .clear
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.title = "Messages"
        column.resizingMask = .autoresizingMask
        historyTable.addTableColumn(column)
        historyScroll.documentView = historyTable

        emptyHistoryLabel.font = .systemFont(ofSize: 13)
        emptyHistoryLabel.textColor = .secondaryLabelColor

        let historyButtons = NSStackView()
        historyButtons.translatesAutoresizingMaskIntoConstraints = false
        historyButtons.orientation = .horizontal
        historyButtons.spacing = 10
        let copyButton = NSButton(title: "Copy Selected", target: self, action: #selector(copySelectedHistory))
        copyButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistoryTapped))
        clearButton.bezelStyle = .rounded
        historyButtons.addArrangedSubview(copyButton)
        historyButtons.addArrangedSubview(clearButton)

        [historyHeader, emptyHistoryLabel, historyScroll, historyButtons].forEach { historyStack.addArrangedSubview($0) }
        card.addSubview(historyStack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            historyStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            historyStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            historyStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            historyStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),

            historyScroll.widthAnchor.constraint(equalTo: historyStack.widthAnchor),
            historyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
    }

    @objc
    private func clearHistoryTapped() {
        onClearHistory?()
    }

    @objc
    private func copySelectedHistory() {
        let row = historyTable.selectedRow
        guard history.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history[row].text, forType: .string)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard history.indices.contains(row) else { return nil }
        let entry = history[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 12
        cell.layer?.cornerCurve = .continuous
        cell.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor

        let titleTag = 101
        let subtitleTag = 102
        let titleField: NSTextField
        let subtitleField: NSTextField

        if let existingTitle = cell.viewWithTag(titleTag) as? NSTextField,
           let existingSubtitle = cell.viewWithTag(subtitleTag) as? NSTextField {
            titleField = existingTitle
            subtitleField = existingSubtitle
        } else {
            let title = NSTextField(labelWithString: "")
            title.tag = titleTag
            title.translatesAutoresizingMaskIntoConstraints = false
            title.font = .systemFont(ofSize: 12, weight: .medium)
            title.textColor = .secondaryLabelColor

            let subtitle = NSTextField(labelWithString: "")
            subtitle.tag = subtitleTag
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            subtitle.font = .systemFont(ofSize: 14)
            subtitle.lineBreakMode = .byTruncatingTail

            cell.addSubview(title)
            cell.addSubview(subtitle)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 10),
                subtitle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                subtitle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
                subtitle.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -10)
            ])
            titleField = title
            subtitleField = subtitle
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        titleField.stringValue = "\(formatter.string(from: entry.createdAt))  ·  \(entry.provider)"
        subtitleField.stringValue = entry.text
        return cell
    }
}
