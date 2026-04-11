import AppKit
import Foundation

final class ControlCenterHeaderView: NSView {
    private let providerBadgeValueLabel = NSTextField(labelWithString: "")
    private let hotkeyBadgeValueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(providerName: String, hotkeyDisplayName: String) {
        providerBadgeValueLabel.stringValue = providerName
        hotkeyBadgeValueLabel.stringValue = hotkeyDisplayName
    }

    private func setupUI() {
        let card = controlCenterCardView()
        addSubview(card)

        let headerStack = NSStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.distribution = .fill
        headerStack.spacing = 22

        let brandIcon = NSImageView(image: controlCenterBrandIcon(size: 64))
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.imageScaling = .scaleAxesIndependently
        NSLayoutConstraint.activate([
            brandIcon.widthAnchor.constraint(equalToConstant: 64),
            brandIcon.heightAnchor.constraint(equalToConstant: 64)
        ])

        let titleStack = NSStackView()
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 8

        let titleLabel = NSTextField(labelWithString: "SpeakFlow Workspace")
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabelColor

        let providerBadge = controlCenterBadge(title: "Provider", valueLabel: providerBadgeValueLabel)
        let hotkeyBadge = controlCenterBadge(title: "Global Key", valueLabel: hotkeyBadgeValueLabel)
        let badgeColumn = NSStackView()
        badgeColumn.translatesAutoresizingMaskIntoConstraints = false
        badgeColumn.orientation = .vertical
        badgeColumn.alignment = .trailing
        badgeColumn.spacing = 12
        badgeColumn.addArrangedSubview(hotkeyBadge)

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)
        titleStack.addArrangedSubview(providerBadge)

        headerStack.addArrangedSubview(brandIcon)
        headerStack.addArrangedSubview(titleStack)
        headerStack.addArrangedSubview(NSView())
        headerStack.addArrangedSubview(badgeColumn)
        card.addSubview(headerStack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            headerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            headerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])

        subtitleLabel.stringValue = "Voice keyboard for every macOS app, with reliable dictation history, calmer controls, and a cleaner daily workflow."
    }
}
