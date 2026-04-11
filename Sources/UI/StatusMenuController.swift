import AppKit
import Foundation

final class StatusMenuController: NSObject {
    struct Actions {
        let toggleRecording: () -> Void
        let openControlCenter: () -> Void
        let pasteLastResult: () -> Void
        let copyLastResult: () -> Void
        let openConfig: () -> Void
        let resetWidgetPosition: () -> Void
        let quit: () -> Void
    }

    private let actions: Actions
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusSummaryItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let hotKeyInfoItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
    private lazy var toggleRecordingItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleRecording), keyEquivalent: "")
    private lazy var pasteLastItem = NSMenuItem(title: "Paste Last Result Again", action: #selector(pasteLastResult), keyEquivalent: "")
    private lazy var copyLastItem = NSMenuItem(title: "Copy Last Result", action: #selector(copyLastResult), keyEquivalent: "")
    private lazy var controlCenterItem = NSMenuItem(title: "Open Settings & History…", action: #selector(openControlCenter), keyEquivalent: ",")
    private lazy var openConfigItem = NSMenuItem(title: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
    private lazy var resetWidgetItem = NSMenuItem(title: "Reset Widget Position", action: #selector(resetWidgetPosition), keyEquivalent: "")
    private lazy var quitItem = NSMenuItem(title: "Quit SpeakFlow", action: #selector(quitApp), keyEquivalent: "q")

    init(actions: Actions) {
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
    }

    func update(state: DictationState, hotkeyDisplayName: String, hasLastOutput: Bool) {
        switch state {
        case .idle:
            toggleRecordingItem.title = "Start Dictation"
            statusSummaryItem.title = "Ready to dictate"
        case .recording:
            toggleRecordingItem.title = "Stop Dictation"
            statusSummaryItem.title = "Listening now"
        case .transcribing:
            toggleRecordingItem.title = "Processing Audio..."
            statusSummaryItem.title = "Finalizing transcript"
        }

        toggleRecordingItem.isEnabled = state != .transcribing
        pasteLastItem.isEnabled = hasLastOutput
        copyLastItem.isEnabled = hasLastOutput
        hotKeyInfoItem.title = "Hotkey: \(hotkeyDisplayName)"

        if let button = statusItem.button {
            button.image = makeStatusBarIcon(for: state)
            button.toolTip = tooltipText(for: state)
        }
    }

    private func buildMenu() {
        statusSummaryItem.isEnabled = false
        hotKeyInfoItem.isEnabled = false

        toggleRecordingItem.target = self
        pasteLastItem.target = self
        copyLastItem.target = self
        controlCenterItem.target = self
        openConfigItem.target = self
        resetWidgetItem.target = self
        quitItem.target = self

        menu.removeAllItems()
        menu.addItem(statusSummaryItem)
        menu.addItem(hotKeyInfoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleRecordingItem)
        menu.addItem(controlCenterItem)
        menu.addItem(pasteLastItem)
        menu.addItem(copyLastItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openConfigItem)
        menu.addItem(resetWidgetItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeStatusBarIcon(for state: DictationState) -> NSImage {
        let image: NSImage
        switch state {
        case .idle:
            image = makePulseImage(size: NSSize(width: 18, height: 18), color: .labelColor, template: true)
        case .recording:
            image = makePulseImage(size: NSSize(width: 18, height: 18), color: .controlAccentColor, template: false)
        case .transcribing:
            image = makePulseImage(size: NSSize(width: 18, height: 18), color: .secondaryLabelColor, template: true)
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func tooltipText(for state: DictationState) -> String {
        switch state {
        case .idle:
            return "\(appDisplayName)\nReady to dictate"
        case .recording:
            return "\(appDisplayName)\nRecording..."
        case .transcribing:
            return "\(appDisplayName)\nTranscribing and cleaning text..."
        }
    }

    @objc
    private func toggleRecording() {
        actions.toggleRecording()
    }

    @objc
    private func openControlCenter() {
        actions.openControlCenter()
    }

    @objc
    private func pasteLastResult() {
        actions.pasteLastResult()
    }

    @objc
    private func copyLastResult() {
        actions.copyLastResult()
    }

    @objc
    private func openConfig() {
        actions.openConfig()
    }

    @objc
    private func resetWidgetPosition() {
        actions.resetWidgetPosition()
    }

    @objc
    private func quitApp() {
        actions.quit()
    }
}
