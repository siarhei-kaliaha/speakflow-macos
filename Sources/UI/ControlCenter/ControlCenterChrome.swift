import AppKit
import Foundation

func controlCenterCardView() -> NSView {
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

func controlCenterSectionTitle(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .semibold)
    return label
}

func controlCenterInfoRow(title: String, valueLabel: NSTextField) -> NSView {
    let row = NSStackView()
    row.translatesAutoresizingMaskIntoConstraints = false
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

func controlCenterComboRow(title: String, comboBox: NSComboBox) -> NSView {
    let row = NSStackView()
    row.translatesAutoresizingMaskIntoConstraints = false
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

func controlCenterBadge(title: String, valueLabel: NSTextField) -> NSView {
    let wrapper = controlCenterCardView()
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

func controlCenterBrandIcon(size: CGFloat) -> NSImage {
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
