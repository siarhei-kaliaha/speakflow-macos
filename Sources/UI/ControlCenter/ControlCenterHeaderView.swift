import AppKit
import Foundation

final class ControlCenterHeaderView: NSView {
    private let providerValueLabel = NSTextField(labelWithString: "")
    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let modeValueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(providerName: String, hotkeyDisplayName: String, activeCaptureMode: CaptureMode?) {
        providerValueLabel.stringValue = providerName
        hotkeyValueLabel.stringValue = hotkeyDisplayName
        modeValueLabel.stringValue = activeCaptureMode?.displayName ?? "Ready"
        subtitleLabel.stringValue = activeCaptureMode == .recording
            ? "Recording mode is active."
            : "Ready to dictate into the current app."
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = ControlCenterChrome.windowBackground.withAlphaComponent(0.88).cgColor
        layer?.borderColor = ControlCenterChrome.borderLight.cgColor
        layer?.borderWidth = 1

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fill
        row.spacing = 16
        addSubview(row)

        let titleStack = NSStackView()
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 6

        let titleLabel = NSTextField(labelWithString: "SpeakFlow")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = ControlCenterChrome.titleColor

        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = ControlCenterChrome.bodyColor

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)

        let tags = NSStackView()
        tags.translatesAutoresizingMaskIntoConstraints = false
        tags.orientation = .horizontal
        tags.alignment = .top
        tags.spacing = 12
        tags.addArrangedSubview(controlCenterTag(title: "Mode", valueLabel: modeValueLabel))
        tags.addArrangedSubview(controlCenterTag(title: "Hotkey", valueLabel: hotkeyValueLabel))
        tags.addArrangedSubview(controlCenterTag(title: "Provider", valueLabel: providerValueLabel))

        row.addArrangedSubview(titleStack)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(tags)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        subtitleLabel.stringValue = "Ready to dictate into the current app."
    }
}
