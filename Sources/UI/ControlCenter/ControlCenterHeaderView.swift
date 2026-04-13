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

        let brandIconCard = controlCenterCardView()
        brandIconCard.layer?.cornerRadius = 18
        let brandIcon = NSImageView(image: controlCenterBrandIcon(size: 60))
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIconCard.addSubview(brandIcon)
        NSLayoutConstraint.activate([
            brandIconCard.widthAnchor.constraint(equalToConstant: 78),
            brandIconCard.heightAnchor.constraint(equalToConstant: 78),
            brandIcon.centerXAnchor.constraint(equalTo: brandIconCard.centerXAnchor),
            brandIcon.centerYAnchor.constraint(equalTo: brandIconCard.centerYAnchor),
            brandIcon.widthAnchor.constraint(equalToConstant: 60),
            brandIcon.heightAnchor.constraint(equalToConstant: 60)
        ])

        let titleStack = NSStackView()
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 8

        let eyebrowLabel = NSTextField(labelWithString: "VOICE CONTROL CENTER")
        eyebrowLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        eyebrowLabel.textColor = ControlCenterChrome.secondaryAccentColor

        let titleLabel = NSTextField(labelWithString: "SpeakFlow Control Center")
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = ControlCenterChrome.titleColor
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = ControlCenterChrome.secondaryColor

        let providerBadge = controlCenterBadge(title: "Provider", valueLabel: providerBadgeValueLabel)
        let hotkeyBadge = controlCenterBadge(title: "Global Key", valueLabel: hotkeyBadgeValueLabel)
        let badgeColumn = NSStackView()
        badgeColumn.translatesAutoresizingMaskIntoConstraints = false
        badgeColumn.orientation = .vertical
        badgeColumn.alignment = .trailing
        badgeColumn.spacing = 12
        badgeColumn.addArrangedSubview(hotkeyBadge)

        titleStack.addArrangedSubview(eyebrowLabel)
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)
        titleStack.addArrangedSubview(providerBadge)

        headerStack.addArrangedSubview(brandIconCard)
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

        subtitleLabel.stringValue = "A polished desktop workspace for dictation, model tuning, hotkey control, and reusable history."
    }
}
