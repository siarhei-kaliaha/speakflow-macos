import AppKit
import Foundation

final class WidgetWindowCoordinator {
    private let onPrimaryClick: () -> Void
    private let onStopClick: () -> Void
    private let onDismissMeeting: () -> Void
    private let onAcceptMeeting: () -> Void
    private var widgetWindows: [WidgetPanel] = []
    private var widgetViews: [WidgetContentView] = []
    private var currentState: WidgetContentView.VisualState = .idle
    private var meetingAppName = "Meeting"
    private var debugLog: (String) -> Void = { _ in }

    init(
        onPrimaryClick: @escaping () -> Void,
        onStopClick: @escaping () -> Void,
        onDismissMeeting: @escaping () -> Void,
        onAcceptMeeting: @escaping () -> Void
    ) {
        self.onPrimaryClick = onPrimaryClick
        self.onStopClick = onStopClick
        self.onDismissMeeting = onDismissMeeting
        self.onAcceptMeeting = onAcceptMeeting
    }

    @MainActor
    func rebuild(debugLog: @escaping (String) -> Void) {
        self.debugLog = debugLog
        widgetWindows.forEach { $0.orderOut(nil) }
        widgetWindows.removeAll()
        widgetViews.removeAll()

        for screen in NSScreen.screens {
            let frame = defaultWidgetFrame(on: screen, size: WidgetTheme.widgetOuterSize(for: currentState))
            let window = WidgetPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            let view = WidgetContentView(frame: NSRect(origin: .zero, size: frame.size))
            view.onToggle = onPrimaryClick
            view.onStopRecording = onStopClick
            view.onDismissMeeting = onDismissMeeting
            view.onAcceptMeeting = onAcceptMeeting
            view.updateMeetingPrompt(appName: meetingAppName)
            view.apply(state: currentState)
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.ignoresMouseEvents = false
            window.isMovable = false
            window.contentView = view
            window.orderFrontRegardless()
            widgetWindows.append(window)
            widgetViews.append(view)
            debugLog("Widget built at frame \(NSStringFromRect(frame))")
        }

        positionWindows(animated: false, debugLog: debugLog)
    }

    @MainActor
    func update(state: WidgetContentView.VisualState) {
        currentState = state
        resizeAndRepositionForCurrentState()
        widgetViews.forEach { $0.apply(state: state) }
    }

    @MainActor
    func updateMeetingPrompt(appName: String?) {
        if let appName, !appName.isEmpty {
            meetingAppName = appName
        } else {
            meetingAppName = "Meeting"
        }
        widgetViews.forEach { $0.updateMeetingPrompt(appName: meetingAppName) }
    }

    @MainActor
    func updateAudioLevels(_ levels: [CGFloat]) {
        widgetViews.forEach { $0.updateAudioLevels(levels) }
    }

    @MainActor
    func updateTimer(startDate: Date?, frozenDuration: TimeInterval?) {
        widgetViews.forEach { $0.updateTimer(startDate: startDate, frozenDuration: frozenDuration) }
    }

    @MainActor
    func resetLayout(debugLog: @escaping (String) -> Void) {
        positionWindows(animated: true, debugLog: debugLog)
    }

    @MainActor
    func refreshForScreenChanges(debugLog: @escaping (String) -> Void) {
        rebuild(debugLog: debugLog)
    }

    @MainActor
    func moveToPreferredScreen(animated: Bool, debugLog: @escaping (String) -> Void) {
        positionWindows(animated: animated, debugLog: debugLog)
    }

    @MainActor
    func bringToFront() {
        widgetWindows.forEach { $0.orderFrontRegardless() }
    }

    @MainActor
    func hideVisibleWindows() -> [WidgetPanel] {
        let visible = widgetWindows.filter(\.isVisible)
        visible.forEach { $0.orderOut(nil) }
        return visible
    }

    @MainActor
    func restoreWindows(_ windows: [WidgetPanel]) {
        windows.forEach { $0.orderFrontRegardless() }
    }

    @MainActor
    private func positionWindows(animated: Bool, debugLog: @escaping (String) -> Void) {
        let screens = NSScreen.screens
        if screens.count != widgetWindows.count {
            rebuild(debugLog: debugLog)
            return
        }

        let targetSize = WidgetTheme.widgetOuterSize(for: currentState)
        for (window, screen) in zip(widgetWindows, screens) {
            let targetFrame = defaultWidgetFrame(on: screen, size: targetSize)
            window.setFrame(targetFrame, display: true, animate: animated)
            debugLog("Widget moved to screen frame \(NSStringFromRect(targetFrame))")
        }
        bringToFront()
    }

    @MainActor
    private func resizeAndRepositionForCurrentState() {
        let targetSize = WidgetTheme.widgetOuterSize(for: currentState)
        let screens = NSScreen.screens
        guard screens.count == widgetWindows.count else {
            rebuild(debugLog: debugLog)
            return
        }

        for (window, screen) in zip(widgetWindows, screens) {
            let targetFrame = defaultWidgetFrame(on: screen, size: targetSize)
            window.setFrame(targetFrame, display: true, animate: true)
        }
        bringToFront()
    }

    private func defaultWidgetFrame(on screen: NSScreen, size: NSSize) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 34
        )
        return NSRect(origin: origin, size: size)
    }
}
