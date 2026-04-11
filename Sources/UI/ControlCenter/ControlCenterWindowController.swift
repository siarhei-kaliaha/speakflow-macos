import AppKit
import Foundation

final class ControlCenterWindowController: NSWindowController {
    var onBeginHotkeyCapture: (() -> Void)?
    var onOpenConfigFile: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onUpdateRealtimeModel: ((String) -> Void)?
    var onUpdateBatchModel: ((String) -> Void)?
    var onUpdateCleanupModel: ((String) -> Void)?

    private let headerView = ControlCenterHeaderView()
    private let metricsView = ControlCenterMetricsView()
    private let controlsView = ControlCenterControlsView()
    private let historyView = ControlCenterHistoryView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeakFlow Workspace"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(config: AppConfig, history: [HistoryEntry], stats: UsageStats, isCapturingHotkey: Bool) {
        headerView.update(
            providerName: config.providerName,
            hotkeyDisplayName: config.resolvedHotkeyBinding().displayName
        )
        metricsView.update(stats: stats)
        controlsView.update(config: config, isCapturingHotkey: isCapturingHotkey)
        historyView.update(history: history)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        controlsView.onBeginHotkeyCapture = { [weak self] in
            self?.onBeginHotkeyCapture?()
        }
        controlsView.onOpenConfigFile = { [weak self] in
            self?.onOpenConfigFile?()
        }
        controlsView.onUpdateRealtimeModel = { [weak self] value in
            self?.onUpdateRealtimeModel?(value)
        }
        controlsView.onUpdateBatchModel = { [weak self] value in
            self?.onUpdateBatchModel?(value)
        }
        controlsView.onUpdateCleanupModel = { [weak self] value in
            self?.onUpdateCleanupModel?(value)
        }
        historyView.onClearHistory = { [weak self] in
            self?.onClearHistory?()
        }

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20

        root.addArrangedSubview(headerView)
        root.addArrangedSubview(metricsView)

        let bodySplit = NSStackView()
        bodySplit.translatesAutoresizingMaskIntoConstraints = false
        bodySplit.orientation = .horizontal
        bodySplit.alignment = .top
        bodySplit.distribution = .fill
        bodySplit.spacing = 18
        bodySplit.addArrangedSubview(controlsView)
        bodySplit.addArrangedSubview(historyView)
        root.addArrangedSubview(bodySplit)

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -26),

            bodySplit.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }
}
