import AppKit
import Foundation

final class ControlCenterRecordingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onClearLibrary: (() -> Void)?
    var onSummarizeCapture: ((UUID) -> Void)?

    private let recordingsTable = NSTableView()
    private let emptyStateLabel = NSTextField(labelWithString: "Click the widget once to start a recording session. Finished sessions will appear here with transcript and summary tools.")
    private let listView = NSView()
    private let detailView = NSView()
    private let transcriptTextView = NSTextView()
    private let summaryTextView = NSTextView()
    private let durationValueLabel = NSTextField(labelWithString: "—")
    private let timestampValueLabel = NSTextField(labelWithString: "—")
    private let providerValueLabel = NSTextField(labelWithString: "—")
    private let copyTranscriptButton = NSButton()
    private let copySummaryButton = NSButton()
    private let summarizeButton = NSButton()
    private let backButton = NSButton()
    private var captures: [CaptureRecord] = []
    private var selectedCaptureID: UUID?
    private var summarizingCaptureID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(captures: [CaptureRecord], summarizingCaptureID: UUID?) {
        self.captures = captures.filter { $0.kind == .recordingSession }
        self.summarizingCaptureID = summarizingCaptureID
        recordingsTable.reloadData()
        emptyStateLabel.isHidden = !self.captures.isEmpty

        if let selectedCaptureID, captures.contains(where: { $0.id == selectedCaptureID }) == false {
            self.selectedCaptureID = nil
        }

        if self.selectedCaptureID == nil {
            showList()
        } else {
            showDetail()
        }
        refreshDetailPane()
    }

    private func setupUI() {
        heightAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true

        addSubview(listView)
        addSubview(detailView)
        listView.translatesAutoresizingMaskIntoConstraints = false
        detailView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            listView.leadingAnchor.constraint(equalTo: leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: trailingAnchor),
            listView.topAnchor.constraint(equalTo: topAnchor),
            listView.bottomAnchor.constraint(equalTo: bottomAnchor),

            detailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailView.topAnchor.constraint(equalTo: topAnchor),
            detailView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        buildListView()
        buildDetailView()
        showList()
    }

    private func buildListView() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 24
        listView.addSubview(stack)

        let topRow = NSStackView()
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.orientation = .horizontal
        topRow.alignment = .bottom
        topRow.distribution = .fill

        let intro = NSStackView()
        intro.translatesAutoresizingMaskIntoConstraints = false
        intro.orientation = .vertical
        intro.alignment = .width
        intro.spacing = 8
        intro.addArrangedSubview(controlCenterSectionTitle("Recording Library"))
        intro.addArrangedSubview(controlCenterSectionCaption("Sticky-recording sessions saved here for deep review and summarization."))

        let clearButton = NSButton(title: "Clear Library", target: self, action: #selector(clearLibraryTapped))
        controlCenterStyleButton(clearButton, style: .secondary)

        topRow.addArrangedSubview(intro)
        topRow.addArrangedSubview(NSView())
        topRow.addArrangedSubview(clearButton)

        let tableContainer = controlCenterPanelView(cornerRadius: 8)
        let tableHeader = makeTableHeader()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        recordingsTable.headerView = nil
        recordingsTable.rowHeight = 56
        recordingsTable.intercellSpacing = .zero
        recordingsTable.selectionHighlightStyle = .regular
        recordingsTable.backgroundColor = .clear
        recordingsTable.delegate = self
        recordingsTable.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recording"))
        column.resizingMask = .autoresizingMask
        recordingsTable.addTableColumn(column)
        scroll.documentView = recordingsTable

        tableContainer.addSubview(tableHeader)
        tableContainer.addSubview(scroll)

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(tableContainer)
        stack.addArrangedSubview(emptyStateLabel)

        emptyStateLabel.font = .systemFont(ofSize: 13)
        emptyStateLabel.textColor = ControlCenterChrome.secondaryColor
        emptyStateLabel.maximumNumberOfLines = 0

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: listView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: listView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: listView.topAnchor),
            listView.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor),

            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tableContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyStateLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),

            tableHeader.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
            tableHeader.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            tableHeader.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            tableHeader.heightAnchor.constraint(equalToConstant: 48),

            scroll.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: tableHeader.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
    }

    private func buildDetailView() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 32
        detailView.addSubview(stack)

        let toolbar = NSStackView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.distribution = .fill

        backButton.title = "Back to Library"
        backButton.target = self
        backButton.action = #selector(backTapped)
        controlCenterStyleButton(backButton, style: .ghost)

        let dangerButton = NSButton(title: "Delete", target: nil, action: nil)
        controlCenterStyleButton(dangerButton, style: .secondary)
        dangerButton.contentTintColor = NSColor.systemRed

        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(dangerButton)

        let metaGrid = NSGridView(views: [
            [makeMetaLabel("Recorded"), timestampValueLabel],
            [makeMetaLabel("Provider"), providerValueLabel]
        ])
        metaGrid.translatesAutoresizingMaskIntoConstraints = false
        metaGrid.rowSpacing = 8
        metaGrid.columnSpacing = 24
        durationValueLabel.isHidden = true

        let transcriptPane = buildDocumentPane(title: "Full Transcript", textView: transcriptTextView, actionButtons: [copyTranscriptButton])
        let summaryPane = buildDocumentPane(title: "Summary", textView: summaryTextView, actionButtons: [summarizeButton, copySummaryButton])

        copyTranscriptButton.title = "Copy Text"
        copyTranscriptButton.target = self
        copyTranscriptButton.action = #selector(copyTranscriptTapped)
        controlCenterStyleButton(copyTranscriptButton, style: .primary)

        summarizeButton.title = "Generate Summary"
        summarizeButton.target = self
        summarizeButton.action = #selector(summarizeTapped)
        controlCenterStyleButton(summarizeButton, style: .secondary)

        copySummaryButton.title = "Copy Summary"
        copySummaryButton.target = self
        copySummaryButton.action = #selector(copySummaryTapped)
        controlCenterStyleButton(copySummaryButton, style: .secondary)

        transcriptTextView.font = .systemFont(ofSize: 15)
        transcriptTextView.textColor = ControlCenterChrome.titleColor
        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = true
        transcriptTextView.drawsBackground = false
        transcriptTextView.textContainerInset = NSSize(width: 0, height: 4)

        summaryTextView.font = .systemFont(ofSize: 15)
        summaryTextView.textColor = ControlCenterChrome.bodyColor
        summaryTextView.isEditable = false
        summaryTextView.isSelectable = true
        summaryTextView.drawsBackground = false
        summaryTextView.textContainerInset = NSSize(width: 0, height: 4)

        stack.addArrangedSubview(toolbar)
        stack.addArrangedSubview(metaGrid)
        stack.addArrangedSubview(transcriptPane)
        stack.addArrangedSubview(summaryPane)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: detailView.topAnchor),
            detailView.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor),

            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            transcriptPane.widthAnchor.constraint(equalTo: stack.widthAnchor),
            summaryPane.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeTableHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = ControlCenterChrome.surfaceBackground.cgColor

        let grid = NSGridView(views: [[
            makeHeaderLabel("Date & Time"),
            makeHeaderLabel("Duration"),
            makeHeaderLabel("Preview"),
            makeHeaderLabel("Status")
        ]])
        grid.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(grid)
        grid.column(at: 0).width = 200
        grid.column(at: 1).width = 100
        grid.column(at: 2).width = 420
        grid.column(at: 3).width = 120
        grid.rowSpacing = 0
        grid.columnSpacing = 16

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            grid.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        return header
    }

    private func makeHeaderLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = ControlCenterChrome.secondaryColor
        return label
    }

    private func makeMetaLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = ControlCenterChrome.secondaryColor
        return label
    }

    private func buildDocumentPane(title: String, textView: NSTextView, actionButtons: [NSButton]) -> NSView {
        let pane = controlCenterPanelView(cornerRadius: 8)

        let header = NSStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        pane.addSubview(header)

        let titleLabel = controlCenterSectionTitle(title)
        let actionRow = NSStackView()
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 12
        actionButtons.forEach { actionRow.addArrangedSubview($0) }

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(actionRow)

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = ControlCenterChrome.borderLight.cgColor
        pane.addSubview(separator)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        pane.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: pane.topAnchor, constant: 18),

            separator.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            separator.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 18),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -18),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])

        return pane
    }

    private func showList() {
        listView.isHidden = false
        detailView.isHidden = true
    }

    private func showDetail() {
        listView.isHidden = true
        detailView.isHidden = false
    }

    private func refreshDetailPane() {
        guard let capture = selectedCapture else {
            timestampValueLabel.stringValue = "—"
            providerValueLabel.stringValue = "—"
            transcriptTextView.string = ""
            summaryTextView.string = "No summary has been generated for this session yet. Click the button above to generate one using GPT."
            copyTranscriptButton.isEnabled = false
            summarizeButton.isEnabled = false
            copySummaryButton.isEnabled = false
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy 'at' HH:mm"
        timestampValueLabel.stringValue = "\(formatter.string(from: capture.endedAt)) (\(format(duration: capture.durationSeconds)))"
        providerValueLabel.stringValue = capture.provider
        transcriptTextView.string = capture.finalText

        let summary = capture.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        summaryTextView.string = (summary?.isEmpty == false)
            ? summary!
            : "No summary has been generated for this session yet. Click the button above to generate one using GPT."

        copyTranscriptButton.isEnabled = !capture.finalText.isEmpty
        let isSummarizing = summarizingCaptureID == capture.id
        summarizeButton.isEnabled = !isSummarizing
        summarizeButton.title = isSummarizing ? "Summarizing…" : "Generate Summary"
        copySummaryButton.isEnabled = summary?.isEmpty == false
    }

    private var selectedCapture: CaptureRecord? {
        guard let selectedCaptureID else { return nil }
        return captures.first(where: { $0.id == selectedCaptureID })
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        captures.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = recordingsTable.selectedRow
        guard captures.indices.contains(row) else { return }
        selectedCaptureID = captures[row].id
        refreshDetailPane()
        showDetail()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard captures.indices.contains(row) else { return nil }
        let capture = captures[row]
        let identifier = NSUserInterfaceItemIdentifier("RecordingCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.clear.cgColor

        let gridIdentifier = NSUserInterfaceItemIdentifier("RecordingGrid")
        let separatorIdentifier = NSUserInterfaceItemIdentifier("RecordingSeparator")
        let grid: NSGridView

        if let existing = cell.subviews.first(where: { $0.identifier == gridIdentifier }) as? NSGridView {
            grid = existing
        } else {
            grid = NSGridView(views: [[
                NSTextField(labelWithString: ""),
                NSTextField(labelWithString: ""),
                NSTextField(labelWithString: ""),
                NSTextField(labelWithString: "")
            ]])
            grid.identifier = gridIdentifier
            grid.translatesAutoresizingMaskIntoConstraints = false
            grid.column(at: 0).width = 200
            grid.column(at: 1).width = 100
            grid.column(at: 2).width = 420
            grid.column(at: 3).width = 120
            grid.columnSpacing = 16
            cell.addSubview(grid)

            let separator = NSView()
            separator.identifier = separatorIdentifier
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.wantsLayer = true
            separator.layer?.backgroundColor = ControlCenterChrome.borderLight.cgColor
            cell.addSubview(separator)

            NSLayoutConstraint.activate([
                grid.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
                grid.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -24),
                grid.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                separator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
                separator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -24),
                separator.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1)
            ])
        }

        let dateLabel = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView as! NSTextField
        let durationLabel = grid.cell(atColumnIndex: 1, rowIndex: 0).contentView as! NSTextField
        let previewLabel = grid.cell(atColumnIndex: 2, rowIndex: 0).contentView as! NSTextField
        let statusLabel = grid.cell(atColumnIndex: 3, rowIndex: 0).contentView as! NSTextField

        [dateLabel, durationLabel, previewLabel, statusLabel].forEach {
            $0.font = .systemFont(ofSize: 14)
            $0.textColor = ControlCenterChrome.titleColor
            $0.lineBreakMode = .byTruncatingTail
        }
        durationLabel.textColor = ControlCenterChrome.secondaryColor
        previewLabel.textColor = ControlCenterChrome.bodyColor
        statusLabel.textColor = ControlCenterChrome.bodyColor

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        dateLabel.stringValue = formatter.string(from: capture.endedAt)
        durationLabel.stringValue = format(duration: capture.durationSeconds)
        previewLabel.stringValue = capture.finalText
        statusLabel.stringValue = capture.summaryStatusText == "Ready" ? "Summary Ready" : "Transcript Ready"

        cell.subviews.first(where: { $0.identifier == separatorIdentifier })?.isHidden = row == captures.count - 1
        return cell
    }

    @objc
    private func clearLibraryTapped() {
        onClearLibrary?()
    }

    @objc
    private func backTapped() {
        showList()
    }

    @objc
    private func copyTranscriptTapped() {
        guard let text = selectedCapture?.finalText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc
    private func summarizeTapped() {
        guard let capture = selectedCapture else { return }
        onSummarizeCapture?(capture.id)
    }

    @objc
    private func copySummaryTapped() {
        guard let summary = selectedCapture?.summary, !summary.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
