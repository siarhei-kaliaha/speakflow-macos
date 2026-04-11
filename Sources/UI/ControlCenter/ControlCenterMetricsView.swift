import AppKit
import Foundation

final class ControlCenterMetricsView: NSView {
    private let dictationsValueLabel = NSTextField(labelWithString: "0")
    private let wordsValueLabel = NSTextField(labelWithString: "0")
    private let charactersValueLabel = NSTextField(labelWithString: "0")
    private let lastUsedValueLabel = NSTextField(labelWithString: "Never")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(stats: UsageStats) {
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
    }

    private func setupUI() {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 16

        [
            makeMetricCard(title: "Dictations", valueLabel: dictationsValueLabel),
            makeMetricCard(title: "Words", valueLabel: wordsValueLabel),
            makeMetricCard(title: "Characters", valueLabel: charactersValueLabel),
            makeMetricCard(title: "Last Used", valueLabel: lastUsedValueLabel)
        ].forEach { row.addArrangedSubview($0) }

        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeMetricCard(title: String, valueLabel: NSTextField) -> NSView {
        let card = controlCenterCardView()
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
}
