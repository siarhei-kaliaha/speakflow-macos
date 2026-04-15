import AppKit
import Foundation

enum ControlCenterButtonStyle {
    case primary
    case secondary
    case ghost
}

enum ControlCenterChrome {
    static let windowBackground = NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.043, alpha: 1)
    static let sidebarBackground = NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)
    static let surfaceBackground = NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.106, alpha: 1)
    static let surfaceHoverBackground = NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1)
    static let borderLight = NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1)
    static let borderStrong = NSColor(calibratedRed: 0.247, green: 0.247, blue: 0.290, alpha: 1)

    static let titleColor = NSColor(calibratedRed: 0.957, green: 0.957, blue: 0.961, alpha: 1)
    static let bodyColor = NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.667, alpha: 1)
    static let secondaryColor = NSColor(calibratedRed: 0.443, green: 0.443, blue: 0.478, alpha: 1)
    static let inverseColor = NSColor.black

    static let accentColor = NSColor(calibratedRed: 0.078, green: 0.722, blue: 0.651, alpha: 1)
    static let accentHoverColor = NSColor(calibratedRed: 0.176, green: 0.831, blue: 0.749, alpha: 1)
    static let accentBackground = NSColor(calibratedRed: 0.078, green: 0.722, blue: 0.651, alpha: 0.15)

    static let sidebarWidth: CGFloat = 260
    static let contentMaxWidth: CGFloat = 960
    static let pagePaddingX: CGFloat = 48
    static let pageTopPadding: CGFloat = 32
    static let pageBottomPadding: CGFloat = 56
    static let sectionGap: CGFloat = 40
    static let idealWindowWidth: CGFloat = 1280
    static let idealWindowHeight: CGFloat = 820
    static let minimumComfortableWindowWidth: CGFloat = sidebarWidth + contentMaxWidth + (pagePaddingX * 2)
    static let minimumComfortableWindowHeight: CGFloat = 760
}

func applyControlCenterBackground(to view: NSView) {
    view.wantsLayer = true
    view.layer?.backgroundColor = ControlCenterChrome.windowBackground.cgColor
}

func controlCenterPanelView(cornerRadius: CGFloat = 8) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.backgroundColor = ControlCenterChrome.surfaceBackground.cgColor
    view.layer?.borderWidth = 1
    view.layer?.borderColor = ControlCenterChrome.borderLight.cgColor
    return view
}

func controlCenterSectionTitle(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.textColor = ControlCenterChrome.titleColor
    return label
}

func controlCenterSectionCaption(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14)
    label.textColor = ControlCenterChrome.bodyColor
    label.maximumNumberOfLines = 0
    return label
}

func controlCenterMetaText(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = ControlCenterChrome.secondaryColor
    return label
}

func controlCenterTag(title: String, valueLabel: NSTextField) -> NSView {
    let view = controlCenterPanelView(cornerRadius: 8)
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2

    let titleLabel = NSTextField(labelWithString: title.uppercased())
    titleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
    titleLabel.textColor = ControlCenterChrome.secondaryColor

    valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
    valueLabel.textColor = ControlCenterChrome.titleColor
    valueLabel.lineBreakMode = .byTruncatingTail
    valueLabel.maximumNumberOfLines = 1

    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(valueLabel)
    view.addSubview(stack)

    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
        stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
    ])

    return view
}

func controlCenterStyleButton(_ button: NSButton, style: ControlCenterButtonStyle) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.wantsLayer = true
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.font = .systemFont(ofSize: 13, weight: .medium)
    button.layer?.cornerRadius = 6
    button.layer?.cornerCurve = .continuous
    button.layer?.borderWidth = 1

    switch style {
    case .primary:
        button.contentTintColor = ControlCenterChrome.accentColor
        button.layer?.backgroundColor = ControlCenterChrome.accentBackground.cgColor
        button.layer?.borderColor = ControlCenterChrome.accentColor.withAlphaComponent(0.3).cgColor
    case .secondary:
        button.contentTintColor = ControlCenterChrome.titleColor
        button.layer?.backgroundColor = ControlCenterChrome.surfaceBackground.cgColor
        button.layer?.borderColor = ControlCenterChrome.borderStrong.cgColor
    case .ghost:
        button.contentTintColor = ControlCenterChrome.bodyColor
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderColor = NSColor.clear.cgColor
    }
}

func controlCenterStyleSidebarButton(_ button: NSButton, selected: Bool) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.wantsLayer = true
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.font = .systemFont(ofSize: 13, weight: .medium)
    button.alignment = .left
    button.imagePosition = .imageLeading
    button.imageScaling = .scaleProportionallyDown
    button.contentTintColor = selected ? ControlCenterChrome.titleColor : ControlCenterChrome.bodyColor
    button.layer?.cornerRadius = 6
    button.layer?.cornerCurve = .continuous
    button.layer?.backgroundColor = selected ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
}

func controlCenterStyleComboBox(_ comboBox: NSComboBox) {
    comboBox.font = .systemFont(ofSize: 13, weight: .medium)
    comboBox.textColor = ControlCenterChrome.titleColor
    comboBox.drawsBackground = true
    comboBox.backgroundColor = ControlCenterChrome.windowBackground
}

func controlCenterBrandIcon(size: CGFloat) -> NSImage {
    if let bundled = loadBundledAppIconImage() {
        bundled.size = NSSize(width: size, height: size)
        return bundled
    }

    return makePulseImage(
        size: NSSize(width: size, height: size),
        color: ControlCenterChrome.bodyColor,
        backgroundColor: ControlCenterChrome.surfaceBackground,
        template: false
    )
}
