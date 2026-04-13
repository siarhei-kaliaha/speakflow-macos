import AppKit
import Foundation

final class ControlCenterHistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onClearHistory: (() -> Void)?

    private let historyTable = NSTableView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "Dictation history will appear here once you start speaking.")
    private let copySelectedButton = NSButton()
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
        copySelectedButton.isEnabled = historyTable.selectedRow >= 0
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
        let historySubtitle = controlCenterSectionCaption("Latest voice outputs, ready to copy, paste, or reuse.")
        let historyHeaderText = NSStackView()
        historyHeaderText.translatesAutoresizingMaskIntoConstraints = false
        historyHeaderText.orientation = .vertical
        historyHeaderText.alignment = .leading
        historyHeaderText.spacing = 4
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
        historyTable.rowHeight = 72
        historyTable.intercellSpacing = NSSize(width: 0, height: 8)
        historyTable.selectionHighlightStyle = .regular
        historyTable.delegate = self
        historyTable.dataSource = self
        historyTable.target = self
        historyTable.doubleAction = #selector(copySelectedHistory)
        historyTable.backgroundColor = .clear
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.title = "Messages"
        column.resizingMask = .autoresizingMask
        historyTable.addTableColumn(column)
        historyScroll.documentView = historyTable

        emptyHistoryLabel.font = .systemFont(ofSize: 13)
        emptyHistoryLabel.textColor = ControlCenterChrome.secondaryColor

        let historyButtons = NSStackView()
        historyButtons.translatesAutoresizingMaskIntoConstraints = false
        historyButtons.orientation = .horizontal
        historyButtons.spacing = 10
        copySelectedButton.title = "Copy Selected"
        copySelectedButton.target = self
        copySelectedButton.action = #selector(copySelectedHistory)
        copySelectedButton.isEnabled = false
        controlCenterStyleButton(copySelectedButton, style: .primary)
        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistoryTapped))
        controlCenterStyleButton(clearButton, style: .secondary)
        historyButtons.addArrangedSubview(copySelectedButton)
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
            historyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 380)
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
        copyHistoryEntry(at: row)
    }

    private func copyHistoryEntry(at row: Int) {
        guard history.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history[row].text, forType: .string)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        copySelectedButton.isEnabled = historyTable.selectedRow >= 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard history.indices.contains(row) else { return nil }
        let entry = history[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 14
        cell.layer?.cornerCurve = .continuous
        cell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        cell.layer?.borderWidth = 1
        cell.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let titleTag = 101
        let subtitleTag = 102
        let copyButtonTag = 103
        let titleField: NSTextField
        let subtitleField: NSTextField
        let copyButton: NSButton

        if let existingTitle = cell.viewWithTag(titleTag) as? NSTextField,
           let existingSubtitle = cell.viewWithTag(subtitleTag) as? NSTextField,
           let existingButton = cell.viewWithTag(copyButtonTag) as? NSButton {
            titleField = existingTitle
            subtitleField = existingSubtitle
            copyButton = existingButton
        } else {
            let title = NSTextField(labelWithString: "")
            title.tag = titleTag
            title.translatesAutoresizingMaskIntoConstraints = false
            title.font = .systemFont(ofSize: 12, weight: .medium)
            title.textColor = ControlCenterChrome.secondaryColor

            let subtitle = NSTextField(labelWithString: "")
            subtitle.tag = subtitleTag
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            subtitle.font = .systemFont(ofSize: 14)
            subtitle.textColor = ControlCenterChrome.bodyColor
            subtitle.lineBreakMode = .byTruncatingTail

            let button = NSButton(title: "Copy", target: self, action: #selector(copyHistoryRowButtonTapped(_:)))
            button.tag = copyButtonTag
            button.translatesAutoresizingMaskIntoConstraints = false
            controlCenterStyleButton(button, style: .subtle)

            cell.addSubview(title)
            cell.addSubview(subtitle)
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
                title.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -10),
                title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 11),
                subtitle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
                subtitle.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -10),
                subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
                subtitle.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -11),
                button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 58)
            ])
            titleField = title
            subtitleField = subtitle
            copyButton = button
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        titleField.stringValue = "\(formatter.string(from: entry.createdAt))  ·  \(entry.provider)"
        subtitleField.stringValue = entry.text
        copyButton.identifier = NSUserInterfaceItemIdentifier("copy-\(row)")
        return cell
    }

    @objc
    private func copyHistoryRowButtonTapped(_ sender: NSButton) {
        guard let rawIdentifier = sender.identifier?.rawValue,
              let row = Int(rawIdentifier.replacingOccurrences(of: "copy-", with: "")) else { return }
        copyHistoryEntry(at: row)
    }
}
