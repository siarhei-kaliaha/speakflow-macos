import AppKit
import Foundation

enum ControlCenterButtonStyle {
    case primary
    case secondary
    case subtle
}

enum ControlCenterChrome {
    static let windowBackgroundTop = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.14, alpha: 1)
    static let windowBackgroundBottom = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1)
    static let cardBackground = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.16, alpha: 0.92)
    static let cardOverlay = NSColor.white.withAlphaComponent(0.025)
    static let cardBorder = NSColor.white.withAlphaComponent(0.10)
    static let cardShadow = NSColor.black.withAlphaComponent(0.32)
    static let titleColor = NSColor.white.withAlphaComponent(0.96)
    static let bodyColor = NSColor.white.withAlphaComponent(0.82)
    static let secondaryColor = NSColor.white.withAlphaComponent(0.56)
    static let accentColor = NSColor(calibratedRed: 0.00, green: 0.90, blue: 1.0, alpha: 1)
    static let secondaryAccentColor = NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.373, alpha: 1.0)
}

func applyControlCenterBackground(to view: NSView) {
    view.wantsLayer = true
    view.layer?.backgroundColor = ControlCenterChrome.windowBackgroundBottom.cgColor

    let gradientName = "ControlCenterWindowGradient"
    view.layer?.sublayers?.removeAll(where: { $0.name == gradientName })

    let gradient = CAGradientLayer()
    gradient.name = gradientName
    gradient.colors = [
        ControlCenterChrome.windowBackgroundTop.cgColor,
        ControlCenterChrome.windowBackgroundBottom.cgColor
    ]
    gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
    gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
    gradient.frame = view.bounds
    gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    view.layer?.insertSublayer(gradient, at: 0)
}

func controlCenterCardView() -> NSView {
    let card = NSView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.wantsLayer = true
    card.layer?.cornerRadius = 20
    card.layer?.cornerCurve = .continuous
    card.layer?.borderWidth = 1
    card.layer?.borderColor = ControlCenterChrome.cardBorder.cgColor
    card.layer?.backgroundColor = ControlCenterChrome.cardBackground.cgColor
    card.layer?.shadowColor = ControlCenterChrome.cardShadow.cgColor
    card.layer?.shadowOpacity = 1
    card.layer?.shadowRadius = 18
    card.layer?.shadowOffset = CGSize(width: 0, height: 12)

    let overlay = CAGradientLayer()
    overlay.colors = [
        ControlCenterChrome.cardOverlay.cgColor,
        NSColor.clear.cgColor
    ]
    overlay.startPoint = CGPoint(x: 0.5, y: 1.0)
    overlay.endPoint = CGPoint(x: 0.5, y: 0.0)
    overlay.cornerRadius = 20
    overlay.cornerCurve = .continuous
    overlay.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
    overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    card.layer?.addSublayer(overlay)
    return card
}

func controlCenterSectionTitle(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = ControlCenterChrome.titleColor
    return label
}

func controlCenterSectionCaption(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12)
    label.textColor = ControlCenterChrome.secondaryColor
    label.maximumNumberOfLines = 0
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
    titleLabel.textColor = ControlCenterChrome.secondaryColor
    valueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    valueLabel.textColor = ControlCenterChrome.bodyColor

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
    titleLabel.textColor = ControlCenterChrome.secondaryColor

    row.addArrangedSubview(titleLabel)
    row.addArrangedSubview(NSView())
    row.addArrangedSubview(comboBox)
    return row
}

func controlCenterBadge(title: String, valueLabel: NSTextField) -> NSView {
    let wrapper = controlCenterCardView()
    wrapper.layer?.cornerRadius = 14

    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 3

    let titleLabel = NSTextField(labelWithString: title.uppercased())
    titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
    titleLabel.textColor = ControlCenterChrome.secondaryColor
    valueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
    valueLabel.textColor = ControlCenterChrome.titleColor

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

func controlCenterStyleButton(_ button: NSButton, style: ControlCenterButtonStyle) {
    button.bezelStyle = .rounded
    button.controlSize = .large
    button.isBordered = true
    button.wantsLayer = true
    button.font = .systemFont(ofSize: 12, weight: .semibold)

    switch style {
    case .primary:
        button.contentTintColor = .white
        button.layer?.backgroundColor = ControlCenterChrome.accentColor.withAlphaComponent(0.20).cgColor
        button.layer?.borderColor = ControlCenterChrome.accentColor.withAlphaComponent(0.36).cgColor
    case .secondary:
        button.contentTintColor = ControlCenterChrome.bodyColor
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    case .subtle:
        button.contentTintColor = ControlCenterChrome.secondaryColor
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    button.layer?.cornerRadius = 10
    button.layer?.cornerCurve = .continuous
    button.layer?.borderWidth = 1
}

func controlCenterStyleComboBox(_ comboBox: NSComboBox) {
    comboBox.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    comboBox.textColor = ControlCenterChrome.titleColor
    comboBox.drawsBackground = true
    comboBox.backgroundColor = NSColor.white.withAlphaComponent(0.06)
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
