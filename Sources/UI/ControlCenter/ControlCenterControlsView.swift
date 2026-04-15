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
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 40
        addSubview(stack)

        let intro = NSStackView()
        intro.translatesAutoresizingMaskIntoConstraints = false
        intro.orientation = .vertical
        intro.alignment = .width
        intro.spacing = 8
        intro.addArrangedSubview(controlCenterSectionTitle("Settings"))
        intro.addArrangedSubview(controlCenterSectionCaption("Configure capture, transcription, cleanup, and clipboard behavior."))

        let shortcutSection = NSStackView()
        shortcutSection.translatesAutoresizingMaskIntoConstraints = false
        shortcutSection.orientation = .vertical
        shortcutSection.alignment = .width
        shortcutSection.spacing = 8

        let shortcutLabel = NSTextField(labelWithString: "Current shortcut")
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutLabel.textColor = ControlCenterChrome.bodyColor

        hotkeyValueLabel.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        hotkeyValueLabel.textColor = ControlCenterChrome.titleColor
        hotkeyHintLabel.font = .systemFont(ofSize: 13)
        hotkeyHintLabel.textColor = ControlCenterChrome.secondaryColor

        captureButton.target = self
        captureButton.action = #selector(beginHotkeyCapture)
        controlCenterStyleButton(captureButton, style: .primary)
        let configButton = NSButton(title: "Open Config File", target: self, action: #selector(openConfigFile))
        controlCenterStyleButton(configButton, style: .secondary)

        let shortcutButtons = NSStackView()
        shortcutButtons.translatesAutoresizingMaskIntoConstraints = false
        shortcutButtons.orientation = .horizontal
        shortcutButtons.alignment = .centerY
        shortcutButtons.spacing = 12
        shortcutButtons.addArrangedSubview(captureButton)
        shortcutButtons.addArrangedSubview(configButton)

        [shortcutLabel, hotkeyValueLabel, hotkeyHintLabel, shortcutButtons].forEach { shortcutSection.addArrangedSubview($0) }

        let captureSection = makeSettingsGroup(
            title: "Capture",
            description: nil,
            content: [
                makeKVRow(key: "Language Hint", valueView: languageValueLabel),
                makeKVRow(key: "Cleanup", valueView: cleanupValueLabel),
                makeKVRow(key: "Clipboard", valueView: clipboardValueLabel)
            ]
        )

        configureModelComboBox(realtimeModelComboBox, presets: elevenLabsRealtimeModelPresets, role: .realtime)
        configureModelComboBox(batchModelComboBox, presets: elevenLabsBatchModelPresets, role: .batch)
        configureModelComboBox(cleanupModelComboBox, presets: openAICleanupModelPresets, role: .cleanup)

        let modelsSection = makeSettingsGroup(
            title: "Transcription Models",
            description: nil,
            content: [
                makeKVRow(key: "Realtime STT", valueView: realtimeModelComboBox),
                makeKVRow(key: "Batch STT", valueView: batchModelComboBox),
                makeKVRow(key: "Cleanup", valueView: cleanupModelComboBox)
            ]
        )

        [intro, shortcutSection, captureSection, modelsSection].forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            bottomAnchor.constraint(equalTo: stack.bottomAnchor),

            intro.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            captureSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelsSection.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeSettingsGroup(title: String, description: String?, content: [NSView]) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = ControlCenterChrome.borderLight.cgColor
        wrapper.addSubview(separator)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        wrapper.addSubview(stack)

        let titleLabel = controlCenterSectionTitle(title)
        stack.addArrangedSubview(titleLabel)

        if let description, !description.isEmpty {
            stack.addArrangedSubview(controlCenterSectionCaption(description))
        }

        content.forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            separator.topAnchor.constraint(equalTo: wrapper.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 24),
            wrapper.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])

        return wrapper
    }

    private func makeKVRow(key: String, valueView: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = ControlCenterChrome.borderLight.cgColor
        row.addSubview(separator)

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keyLabel.textColor = ControlCenterChrome.bodyColor

        valueView.translatesAutoresizingMaskIntoConstraints = false
        if let label = valueView as? NSTextField {
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = ControlCenterChrome.titleColor
            label.alignment = .right
        }

        row.addSubview(keyLabel)
        row.addSubview(valueView)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 56),
            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            keyLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueView.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        ])

        return row
    }

    private func configureModelComboBox(_ comboBox: NSComboBox, presets: [String], role: ModelComboRole) {
        comboBox.isEditable = true
        comboBox.usesDataSource = false
        comboBox.addItems(withObjectValues: presets)
        comboBox.completes = true
        comboBox.delegate = self
        comboBox.target = self
        comboBox.action = #selector(modelComboSelectionChanged(_:))
        comboBox.tag = role.rawValue
        controlCenterStyleComboBox(comboBox)
        comboBox.widthAnchor.constraint(equalToConstant: 240).isActive = true
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
        guard !value.isEmpty, let role = ModelComboRole(rawValue: comboBox.tag) else { return }

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
