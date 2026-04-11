import AppKit
import Foundation
final class ControlCenterWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate, NSControlTextEditingDelegate {
    var onBeginHotkeyCapture: (() -> Void)?
    var onOpenConfigFile: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onUpdateRealtimeModel: ((String) -> Void)?
    var onUpdateBatchModel: ((String) -> Void)?
    var onUpdateCleanupModel: ((String) -> Void)?

    private let providerBadgeLabel = NSTextField(labelWithString: "")
    private let hotkeyBadgeValueLabel = NSTextField(labelWithString: "")
    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let hotkeyHintLabel = NSTextField(labelWithString: "")
    private let heroSubtitleLabel = NSTextField(labelWithString: "")
    private let captureButton = NSButton()
    private let languageValueLabel = NSTextField(labelWithString: "")
    private let cleanupValueLabel = NSTextField(labelWithString: "")
    private let clipboardValueLabel = NSTextField(labelWithString: "")
    private let realtimeModelComboBox = NSComboBox()
    private let batchModelComboBox = NSComboBox()
    private let cleanupModelComboBox = NSComboBox()
    private let dictationsValueLabel = NSTextField(labelWithString: "0")
    private let wordsValueLabel = NSTextField(labelWithString: "0")
    private let charactersValueLabel = NSTextField(labelWithString: "0")
    private let lastUsedValueLabel = NSTextField(labelWithString: "Never")
    private let historyTable = NSTableView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "Dictation history will appear here once you start speaking.")
    private var history: [HistoryEntry] = []
    private var isUpdatingUI = false
    private enum ModelComboRole: Int {
        case realtime = 1
        case batch = 2
        case cleanup = 3
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeakFlow Workspace"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(config: AppConfig, history: [HistoryEntry], stats: UsageStats, isCapturingHotkey: Bool) {
        isUpdatingUI = true
        providerBadgeLabel.stringValue = config.providerName
        hotkeyBadgeValueLabel.stringValue = config.resolvedHotkeyBinding().displayName
        hotkeyValueLabel.stringValue = config.resolvedHotkeyBinding().displayName
        languageValueLabel.stringValue = config.transcriptionLanguageHint.isEmpty ? "Auto detect" : config.transcriptionLanguageHint.uppercased()
        cleanupValueLabel.stringValue = config.cleanupEnabled ? config.cleanupModel : "Disabled"
        clipboardValueLabel.stringValue = config.restoreClipboard ? "Restore after paste" : "Leave latest result"
        realtimeModelComboBox.stringValue = config.elevenLabsRealtimeModel
        batchModelComboBox.stringValue = config.transcriptionModel
        cleanupModelComboBox.stringValue = config.cleanupModel
        hotkeyHintLabel.stringValue = isCapturingHotkey
            ? "Press Fn, Right Command, Right Control, or Ctrl+Option+Space."
            : "Click Change Hotkey, then press the shortcut you want to keep."
        heroSubtitleLabel.stringValue = "Voice keyboard for every macOS app, with reliable dictation history, calmer controls, and a cleaner daily workflow."
        captureButton.title = isCapturingHotkey ? "Listening…" : "Change Hotkey"
        self.history = history
        historyTable.reloadData()
        emptyHistoryLabel.isHidden = !history.isEmpty
        dictationsValueLabel.stringValue = "\(stats.totalDictations)"
        wordsValueLabel.stringValue = "\(stats.totalWords)"
        charactersValueLabel.stringValue = "\(stats.totalCharacters)"
        if let lastUsed = stats.lastDictationAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            lastUsedValueLabel.stringValue = formatter.localizedString(for: lastUsed, relativeTo: Date())
        } else {
            lastUsedValueLabel.stringValue = "Never"
        }
        isUpdatingUI = false
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20

        let headerCard = makeCardView()
        let headerStack = NSStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.distribution = .fill
        headerStack.spacing = 22

        let brandIcon = NSImageView(image: ControlCenterWindowController.makeBrandAppIcon(size: 64))
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.imageScaling = .scaleAxesIndependently
        NSLayoutConstraint.activate([
            brandIcon.widthAnchor.constraint(equalToConstant: 64),
            brandIcon.heightAnchor.constraint(equalToConstant: 64)
        ])

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 8

        let titleLabel = NSTextField(labelWithString: "SpeakFlow Workspace")
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        heroSubtitleLabel.font = .systemFont(ofSize: 14)
        heroSubtitleLabel.textColor = .secondaryLabelColor
        providerBadgeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        providerBadgeLabel.textColor = .secondaryLabelColor

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(heroSubtitleLabel)
        titleStack.addArrangedSubview(providerBadgeLabel)

        let headerBadges = NSStackView()
        headerBadges.orientation = .vertical
        headerBadges.alignment = .trailing
        headerBadges.spacing = 12
        headerBadges.addArrangedSubview(makeBadge(title: "Global Key", valueLabel: hotkeyBadgeValueLabel))

        headerStack.addArrangedSubview(brandIcon)
        headerStack.addArrangedSubview(titleStack)
        headerStack.addArrangedSubview(NSView())
        headerStack.addArrangedSubview(headerBadges)
        headerCard.addSubview(headerStack)

        let metricsRow = NSStackView()
        metricsRow.translatesAutoresizingMaskIntoConstraints = false
        metricsRow.orientation = .horizontal
        metricsRow.alignment = .top
        metricsRow.distribution = .fillEqually
        metricsRow.spacing = 16

        [
            makeMetricCard(title: "Dictations", valueLabel: dictationsValueLabel),
            makeMetricCard(title: "Words", valueLabel: wordsValueLabel),
            makeMetricCard(title: "Characters", valueLabel: charactersValueLabel),
            makeMetricCard(title: "Last Used", valueLabel: lastUsedValueLabel)
        ].forEach { metricsRow.addArrangedSubview($0) }

        let bodySplit = NSStackView()
        bodySplit.translatesAutoresizingMaskIntoConstraints = false
        bodySplit.orientation = .horizontal
        bodySplit.alignment = .top
        bodySplit.distribution = .fill
        bodySplit.spacing = 18

        let controlCard = makeCardView()
        let controlStack = NSStackView()
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.orientation = .vertical
        controlStack.alignment = .leading
        controlStack.spacing = 20

        let controlTitle = sectionTitle("Controls")
        let hotkeySection = NSStackView()
        hotkeySection.orientation = .vertical
        hotkeySection.alignment = .leading
        hotkeySection.spacing = 10
        let hotkeyCaption = NSTextField(labelWithString: "Current shortcut")
        hotkeyCaption.font = .systemFont(ofSize: 12, weight: .medium)
        hotkeyCaption.textColor = .secondaryLabelColor
        hotkeyValueLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        hotkeyHintLabel.font = .systemFont(ofSize: 12)
        hotkeyHintLabel.textColor = .secondaryLabelColor
        captureButton.bezelStyle = .rounded
        captureButton.controlSize = .large
        captureButton.target = self
        captureButton.action = #selector(beginHotkeyCapture)
        let configButton = NSButton(title: "Open Config File", target: self, action: #selector(openConfigFile))
        configButton.bezelStyle = .rounded
        let actionButtons = NSStackView()
        actionButtons.orientation = .horizontal
        actionButtons.alignment = .centerY
        actionButtons.spacing = 10
        actionButtons.addArrangedSubview(captureButton)
        actionButtons.addArrangedSubview(configButton)

        [hotkeyCaption, hotkeyValueLabel, hotkeyHintLabel, actionButtons].forEach { hotkeySection.addArrangedSubview($0) }

        let setupSection = NSStackView()
        setupSection.orientation = .vertical
        setupSection.alignment = .leading
        setupSection.spacing = 10
        setupSection.addArrangedSubview(sectionTitle("Current Setup"))
        setupSection.addArrangedSubview(makeInfoRow(title: "Language Hint", valueLabel: languageValueLabel))
        setupSection.addArrangedSubview(makeInfoRow(title: "Cleanup", valueLabel: cleanupValueLabel))
        setupSection.addArrangedSubview(makeInfoRow(title: "Clipboard", valueLabel: clipboardValueLabel))

        configureModelComboBox(
            realtimeModelComboBox,
            presets: elevenLabsRealtimeModelPresets,
            role: .realtime
        )
        configureModelComboBox(
            batchModelComboBox,
            presets: elevenLabsBatchModelPresets,
            role: .batch
        )
        configureModelComboBox(
            cleanupModelComboBox,
            presets: openAICleanupModelPresets,
            role: .cleanup
        )

        let modelsSection = NSStackView()
        modelsSection.orientation = .vertical
        modelsSection.alignment = .leading
        modelsSection.spacing = 12
        modelsSection.addArrangedSubview(sectionTitle("Model Selection"))
        modelsSection.addArrangedSubview(makeComboRow(title: "Realtime STT", comboBox: realtimeModelComboBox))
        modelsSection.addArrangedSubview(makeComboRow(title: "Batch STT", comboBox: batchModelComboBox))
        modelsSection.addArrangedSubview(makeComboRow(title: "Cleanup", comboBox: cleanupModelComboBox))

        let notesSection = NSStackView()
        notesSection.orientation = .vertical
        notesSection.alignment = .leading
        notesSection.spacing = 8
        let notesTitle = sectionTitle("Operating Notes")
        let notesBody = NSTextField(wrappingLabelWithString: "Short accidental taps are ignored automatically. Silent clips stay quiet. SpeakFlow keeps the widget focused on the screen where you triggered dictation.")
        notesBody.font = .systemFont(ofSize: 12)
        notesBody.textColor = .secondaryLabelColor
        notesBody.maximumNumberOfLines = 0
        notesSection.addArrangedSubview(notesTitle)
        notesSection.addArrangedSubview(notesBody)

        controlStack.addArrangedSubview(controlTitle)
        controlStack.addArrangedSubview(hotkeySection)
        controlStack.addArrangedSubview(setupSection)
        controlStack.addArrangedSubview(modelsSection)
        controlStack.addArrangedSubview(notesSection)
        controlCard.addSubview(controlStack)

        let historyCard = makeCardView()
        let historyStack = NSStackView()
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 16

        let historyHeader = NSStackView()
        historyHeader.orientation = .horizontal
        historyHeader.alignment = .centerY
        historyHeader.spacing = 10
        let historyTitle = sectionTitle("Recent Dictations")
        let historySubtitle = NSTextField(labelWithString: "Latest voice outputs, ready to copy or review.")
        historySubtitle.font = .systemFont(ofSize: 13)
        historySubtitle.textColor = .secondaryLabelColor
        let historyHeaderText = NSStackView()
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
        historyButtons.orientation = .horizontal
        historyButtons.spacing = 10
        let copyButton = NSButton(title: "Copy Selected", target: self, action: #selector(copySelectedHistory))
        copyButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistoryTapped))
        clearButton.bezelStyle = .rounded
        historyButtons.addArrangedSubview(copyButton)
        historyButtons.addArrangedSubview(clearButton)

        historyStack.addArrangedSubview(historyHeader)
        historyStack.addArrangedSubview(emptyHistoryLabel)
        historyStack.addArrangedSubview(historyScroll)
        historyStack.addArrangedSubview(historyButtons)
        historyCard.addSubview(historyStack)

        bodySplit.addArrangedSubview(controlCard)
        bodySplit.addArrangedSubview(historyCard)

        root.addArrangedSubview(headerCard)
        root.addArrangedSubview(metricsRow)
        root.addArrangedSubview(bodySplit)
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -26),

            headerStack.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -24),
            headerStack.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 22),
            headerStack.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -22),

            controlCard.widthAnchor.constraint(equalToConstant: 328),

            controlStack.leadingAnchor.constraint(equalTo: controlCard.leadingAnchor, constant: 22),
            controlStack.trailingAnchor.constraint(equalTo: controlCard.trailingAnchor, constant: -22),
            controlStack.topAnchor.constraint(equalTo: controlCard.topAnchor, constant: 22),
            controlStack.bottomAnchor.constraint(lessThanOrEqualTo: controlCard.bottomAnchor, constant: -22),

            historyStack.leadingAnchor.constraint(equalTo: historyCard.leadingAnchor, constant: 22),
            historyStack.trailingAnchor.constraint(equalTo: historyCard.trailingAnchor, constant: -22),
            historyStack.topAnchor.constraint(equalTo: historyCard.topAnchor, constant: 22),
            historyStack.bottomAnchor.constraint(equalTo: historyCard.bottomAnchor, constant: -22),

            historyScroll.widthAnchor.constraint(equalTo: historyStack.widthAnchor),
            historyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),

            bodySplit.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }

    private func makeCardView() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        return card
    }

    private func makeMetricCard(title: String, valueLabel: NSTextField) -> NSView {
        let card = makeCardView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func makeInfoRow(title: String, valueLabel: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func configureModelComboBox(_ comboBox: NSComboBox, presets: [String], role: ModelComboRole) {
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        comboBox.isEditable = true
        comboBox.usesDataSource = false
        comboBox.addItems(withObjectValues: presets)
        comboBox.completes = true
        comboBox.delegate = self
        comboBox.target = self
        comboBox.action = #selector(modelComboSelectionChanged(_:))
        comboBox.tag = role.rawValue
        comboBox.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        NSLayoutConstraint.activate([
            comboBox.widthAnchor.constraint(equalToConstant: 170)
        ])
    }

    private func makeComboRow(title: String, comboBox: NSComboBox) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(comboBox)
        return row
    }

    @objc
    private func modelComboSelectionChanged(_ sender: NSComboBox) {
        commitModelSelection(for: sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let comboBox = obj.object as? NSComboBox else { return }
        commitModelSelection(for: comboBox)
    }

    private func commitModelSelection(for comboBox: NSComboBox) {
        guard !isUpdatingUI else { return }
        let value = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let role = ModelComboRole(rawValue: comboBox.tag) else { return }

        switch role {
        case .realtime:
            onUpdateRealtimeModel?(value)
        case .batch:
            onUpdateBatchModel?(value)
        case .cleanup:
            onUpdateCleanupModel?(value)
        }
    }

    private func makeBadge(title: String, valueLabel: NSTextField) -> NSView {
        let wrapper = makeCardView()
        wrapper.layer?.cornerRadius = 12
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10)
        ])
        return wrapper
    }

    private static func makeBrandAppIcon(size: CGFloat) -> NSImage {
        if let bundled = loadBundledAppIconImage() {
            bundled.size = NSSize(width: size, height: size)
            return bundled
        }
        return makePulseImage(
            size: NSSize(width: size, height: size),
            color: NSColor.white.withAlphaComponent(0.96),
            backgroundColor: NSColor(calibratedWhite: 0.08, alpha: 1.0),
            template: false
        )
    }

    @objc
    private func beginHotkeyCapture() {
        guard !isUpdatingUI else { return }
        onBeginHotkeyCapture?()
    }

    @objc
    private func openConfigFile() {
        onOpenConfigFile?()
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

