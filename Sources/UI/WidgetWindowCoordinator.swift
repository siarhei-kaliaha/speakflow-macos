import AppKit
import Foundation

final class WidgetWindowCoordinator {
    private let onToggle: () -> Void
    private var widgetWindows: [WidgetPanel] = []
    private var widgetViews: [WidgetContentView] = []

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    @MainActor
    func rebuild(debugLog: (String) -> Void) {
        widgetWindows.forEach { $0.orderOut(nil) }
        widgetWindows.removeAll()
        widgetViews.removeAll()

        for screen in NSScreen.screens {
            let frame = defaultWidgetFrame(on: screen)
            let window = WidgetPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            let view = WidgetContentView(frame: NSRect(origin: .zero, size: frame.size))
            view.onToggle = onToggle
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
        widgetViews.forEach { $0.apply(state: state) }
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
    func resetLayout(debugLog: (String) -> Void) {
        positionWindows(animated: true, debugLog: debugLog)
    }

    @MainActor
    func refreshForScreenChanges(debugLog: (String) -> Void) {
        rebuild(debugLog: debugLog)
    }

    @MainActor
    func moveToPreferredScreen(animated: Bool, debugLog: (String) -> Void) {
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
    private func positionWindows(animated: Bool, debugLog: (String) -> Void) {
        let screens = NSScreen.screens
        if screens.count != widgetWindows.count {
            rebuild(debugLog: debugLog)
            return
        }

        for (window, screen) in zip(widgetWindows, screens) {
            let targetFrame = defaultWidgetFrame(on: screen)
            window.setFrame(targetFrame, display: true, animate: animated)
            debugLog("Widget moved to screen frame \(NSStringFromRect(targetFrame))")
        }
        bringToFront()
    }

    private func defaultWidgetFrame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - widgetOuterSize.width / 2,
            y: visibleFrame.minY + 34
        )
        return NSRect(origin: origin, size: widgetOuterSize)
    }
}
