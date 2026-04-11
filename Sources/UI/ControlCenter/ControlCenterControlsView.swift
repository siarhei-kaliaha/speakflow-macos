import AppKit
import Foundation

final class ControlCenterControlsView: NSView, NSComboBoxDelegate, NSControlTextEditingDelegate {
    enum ModelComboRole: Int {
        case realtime = 1
        case batch = 2
        case cleanup = 3
    }

    var onBeginHotkeyCapture: (() -> Void)?
    var onOpenConfigFile: (() -> Void)?
    var onUpdateRealtimeModel: ((String) -> Void)?
    var onUpdateBatchModel: ((String) -> Void)?
    var onUpdateCleanupModel: ((String) -> Void)?

    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let hotkeyHintLabel = NSTextField(labelWithString: "")
    private let languageValueLabel = NSTextField(labelWithString: "")
    private let cleanupValueLabel = NSTextField(labelWithString: "")
    private let clipboardValueLabel = NSTextField(labelWithString: "")
    private let realtimeModelComboBox = NSComboBox()
    private let batchModelComboBox = NSComboBox()
    private let cleanupModelComboBox = NSComboBox()
    private let captureButton = NSButton()
    private var isUpdatingUI = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(config: AppConfig, isCapturingHotkey: Bool) {
        isUpdatingUI = true
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
        captureButton.title = isCapturingHotkey ? "Listening…" : "Change Hotkey"
        isUpdatingUI = false
    }

    private func setupUI() {
        let card = controlCenterCardView()
        addSubview(card)

        let controlStack = NSStackView()
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.orientation = .vertical
        controlStack.alignment = .leading
        controlStack.spacing = 20

        let controlTitle = controlCenterSectionTitle("Controls")

        let hotkeySection = NSStackView()
        hotkeySection.translatesAutoresizingMaskIntoConstraints = false
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
        actionButtons.translatesAutoresizingMaskIntoConstraints = false
        actionButtons.orientation = .horizontal
        actionButtons.alignment = .centerY
        actionButtons.spacing = 10
        actionButtons.addArrangedSubview(captureButton)
        actionButtons.addArrangedSubview(configButton)
        [hotkeyCaption, hotkeyValueLabel, hotkeyHintLabel, actionButtons].forEach { hotkeySection.addArrangedSubview($0) }

        let setupSection = NSStackView()
        setupSection.translatesAutoresizingMaskIntoConstraints = false
        setupSection.orientation = .vertical
        setupSection.alignment = .leading
        setupSection.spacing = 10
        setupSection.addArrangedSubview(controlCenterSectionTitle("Current Setup"))
        setupSection.addArrangedSubview(controlCenterInfoRow(title: "Language Hint", valueLabel: languageValueLabel))
        setupSection.addArrangedSubview(controlCenterInfoRow(title: "Cleanup", valueLabel: cleanupValueLabel))
        setupSection.addArrangedSubview(controlCenterInfoRow(title: "Clipboard", valueLabel: clipboardValueLabel))

        configureModelComboBox(realtimeModelComboBox, presets: elevenLabsRealtimeModelPresets, role: .realtime)
        configureModelComboBox(batchModelComboBox, presets: elevenLabsBatchModelPresets, role: .batch)
        configureModelComboBox(cleanupModelComboBox, presets: openAICleanupModelPresets, role: .cleanup)

        let modelsSection = NSStackView()
        modelsSection.translatesAutoresizingMaskIntoConstraints = false
        modelsSection.orientation = .vertical
        modelsSection.alignment = .leading
        modelsSection.spacing = 12
        modelsSection.addArrangedSubview(controlCenterSectionTitle("Model Selection"))
        modelsSection.addArrangedSubview(controlCenterComboRow(title: "Realtime STT", comboBox: realtimeModelComboBox))
        modelsSection.addArrangedSubview(controlCenterComboRow(title: "Batch STT", comboBox: batchModelComboBox))
        modelsSection.addArrangedSubview(controlCenterComboRow(title: "Cleanup", comboBox: cleanupModelComboBox))

        let notesSection = NSStackView()
        notesSection.translatesAutoresizingMaskIntoConstraints = false
        notesSection.orientation = .vertical
        notesSection.alignment = .leading
        notesSection.spacing = 8
        let notesTitle = controlCenterSectionTitle("Operating Notes")
        let notesBody = NSTextField(wrappingLabelWithString: "Short accidental taps are ignored automatically. Silent clips stay quiet. SpeakFlow keeps the widget focused on the screen where you triggered dictation.")
        notesBody.font = .systemFont(ofSize: 12)
        notesBody.textColor = .secondaryLabelColor
        notesBody.maximumNumberOfLines = 0
        notesSection.addArrangedSubview(notesTitle)
        notesSection.addArrangedSubview(notesBody)

        [controlTitle, hotkeySection, setupSection, modelsSection, notesSection].forEach { controlStack.addArrangedSubview($0) }
        card.addSubview(controlStack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            card.widthAnchor.constraint(equalToConstant: 328),
            controlStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            controlStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            controlStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            controlStack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -22)
        ])
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
}
