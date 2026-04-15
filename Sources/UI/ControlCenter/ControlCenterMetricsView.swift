import AppKit
import Foundation

final class ControlCenterMetricsView: NSView {
    private let dictationsValueLabel = NSTextField(labelWithString: "0")
    private let recordingsValueLabel = NSTextField(labelWithString: "0")
    private let recordedTimeValueLabel = NSTextField(labelWithString: "00:00")
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
        recordingsValueLabel.stringValue = "\(stats.totalRecordings)"
        recordedTimeValueLabel.stringValue = format(duration: stats.totalRecordedSeconds)
        if let lastUsed = stats.lastCaptureAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            lastUsedValueLabel.stringValue = formatter.localizedString(for: lastUsed, relativeTo: Date())
        } else {
            lastUsedValueLabel.stringValue = "Never"
        }
    }

    private func setupUI() {
        heightAnchor.constraint(equalToConstant: 84).isActive = true

        let bar = controlCenterPanelView(cornerRadius: 8)
        addSubview(bar)

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 0
        bar.addSubview(row)

        [
            makeMetric(title: "Dictations", valueLabel: dictationsValueLabel),
            makeMetric(title: "Recordings", valueLabel: recordingsValueLabel),
            makeMetric(title: "Recorded", valueLabel: recordedTimeValueLabel),
            makeMetric(title: "Last Capture", valueLabel: lastUsedValueLabel)
        ].enumerated().forEach { index, metric in
            if index > 0 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = ControlCenterChrome.borderLight.cgColor
                separator.translatesAutoresizingMaskIntoConstraints = false
                let wrapper = NSView()
                wrapper.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(metric)
                wrapper.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    separator.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    separator.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                    separator.widthAnchor.constraint(equalToConstant: 1),
                    metric.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    metric.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                    metric.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    metric.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
                ])
                row.addArrangedSubview(wrapper)
            } else {
                row.addArrangedSubview(metric)
            }
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            row.topAnchor.constraint(equalTo: bar.topAnchor),
            row.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])
    }

    private func makeMetric(title: String, valueLabel: NSTextField) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        view.addSubview(stack)

        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = ControlCenterChrome.secondaryColor

        valueLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        valueLabel.textColor = ControlCenterChrome.titleColor

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
