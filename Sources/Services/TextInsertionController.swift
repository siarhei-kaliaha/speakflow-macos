import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TextInsertionController {
    struct PasteResult {
        let pasted: Bool
        let statusMessage: String
    }

    private struct CapturedInsertionTarget {
        let element: AXUIElement
        let pid: pid_t
        let originalValue: String
        let originalRange: CFRange
        var lastRenderedText: String
    }

    private var targetApplication: NSRunningApplication?
    private var capturedInsertionTarget: CapturedInsertionTarget?
    private var pendingLiveInsertion: DispatchWorkItem?
    private var lastTriggerMouseLocation = NSPoint.zero
    private let debugLog: (String) -> Void

    init(debugLog: @escaping (String) -> Void) {
        self.debugLog = debugLog
    }

    func requestPlatformPermissionsIfNeeded() {
        _ = PlatformPermissions.accessibility(prompt: true)
        _ = PlatformPermissions.listenEvent(prompt: false)
        _ = PlatformPermissions.postEvent(prompt: false)
    }

    func captureTargetApplication() {
        let currentAppPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetApplication = frontmost?.processIdentifier == currentAppPID ? nil : frontmost
        if let app = targetApplication {
            debugLog("Captured target application: \(app.localizedName ?? "unknown") pid=\(app.processIdentifier)")
        } else {
            debugLog("No external target application captured; will rely on focused system element")
        }
    }

    func updateTriggerLocation(_ point: NSPoint) {
        lastTriggerMouseLocation = point
    }

    func clearTransientState() {
        pendingLiveInsertion?.cancel()
        pendingLiveInsertion = nil
        capturedInsertionTarget = nil
    }

    func prepareForRecording(preferAccessibilityInsertion: Bool) {
        if !preferAccessibilityInsertion {
            capturedInsertionTarget = nil
            debugLog("Live insertion disabled by config")
            return
        }
        capturedInsertionTarget = captureInsertionTarget()
        debugLog("Prepared live insertion target available=\(capturedInsertionTarget != nil)")
    }

    func scheduleLiveInsertion(
        for transcript: String,
        isRecording: Bool,
        preferAccessibilityInsertion: Bool,
        statusHandler: @escaping (String) -> Void
    ) {
        guard isRecording, preferAccessibilityInsertion else {
            debugLog("Skipping live insertion isRecording=\(isRecording) preferAccessibilityInsertion=\(preferAccessibilityInsertion)")
            return
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if capturedInsertionTarget == nil {
            capturedInsertionTarget = captureInsertionTarget()
            debugLog("Live insertion target reacquire attempted success=\(capturedInsertionTarget != nil)")
        }

        pendingLiveInsertion?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.renderCapturedInsertion(trimmed) {
                statusHandler("Live insertion via Accessibility")
                self.debugLog("Live insertion applied textLength=\((trimmed as NSString).length)")
            } else {
                self.debugLog("Live insertion failed for textLength=\((trimmed as NSString).length)")
            }
        }
        pendingLiveInsertion = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    func paste(
        text: String,
        restoreClipboard: Bool,
        hideWidgets: () -> [NSWindow],
        restoreWidgets: @escaping ([NSWindow]) -> Void,
        statusHandler: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        debugLog("Paste requested for textLength=\((text as NSString).length)")
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let hasAccessibility = PlatformPermissions.accessibility(prompt: false)
        if !hasAccessibility {
            _ = PlatformPermissions.accessibility(prompt: true)
            statusHandler("Clipboard only · Accessibility permission missing")
            debugLog("Paste fell back to clipboard only because accessibility is missing")
            completion()
            return
        }

        let visibleWidgets = hideWidgets()
        targetApplication?.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let pasted = self.performMacPaste()
            statusHandler(pasted ? "Clipboard paste" : "Clipboard only")
            self.debugLog("Paste attempt finished pasted=\(pasted)")

            if restoreClipboard {
                let restoreDelay = pasted ? 1.0 : 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    snapshot.restore(to: pasteboard)
                }
            }

            if !visibleWidgets.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    restoreWidgets(visibleWidgets)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                completion()
            }
        }
    }

    private func performMacPaste() -> Bool {
        if PlatformPermissions.postEvent(prompt: false) {
            sendCommandV()
            return true
        }
        return runAppleScriptPasteFallback()
    }

    private func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        usleep(8_000)
        keyUp.post(tap: .cgSessionEventTap)
        usleep(20_000)
    }

    private func runAppleScriptPasteFallback() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            #"tell application "System Events" to key code 9 using command down"#
        ]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func captureInsertionTarget() -> CapturedInsertionTarget? {
        guard PlatformPermissions.accessibility(prompt: false),
              let focusedElement = bestCandidateTextElement()
        else {
            debugLog("Capture insertion target failed: accessibility missing or no writable focused element")
            return nil
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &pid) == .success,
              let currentValue = copyStringAttribute(kAXValueAttribute, from: focusedElement)
        else {
            debugLog("Capture insertion target failed: unable to read AX value")
            return nil
        }

        let currentNSString = currentValue as NSString
        let selectedRange = copySelectedRange(from: focusedElement) ?? CFRange(location: currentNSString.length, length: 0)
        guard validatedRange(selectedRange, in: currentNSString) != nil else {
            debugLog("Capture insertion target failed: invalid selected range")
            return nil
        }

        debugLog("Captured insertion target pid=\(pid) textLength=\(currentNSString.length) range={\(selectedRange.location),\(selectedRange.length)}")
        return CapturedInsertionTarget(
            element: focusedElement,
            pid: pid,
            originalValue: currentValue,
            originalRange: selectedRange,
            lastRenderedText: ""
        )
    }

    private func renderCapturedInsertion(_ text: String) -> Bool {
        guard var target = capturedInsertionTarget else {
            debugLog("Render live insertion skipped: no captured target")
            return false
        }

        let originalNSString = target.originalValue as NSString
        guard let selectedRange = validatedRange(target.originalRange, in: originalNSString) else {
            debugLog("Render live insertion failed: target range is no longer valid")
            return false
        }

        let replacement = originalNSString.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: text
        )
        let setValueResult = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, replacement as CFTypeRef)
        guard setValueResult == .success else {
            debugLog("Render live insertion failed: AX value set result=\(setValueResult.rawValue)")
            return false
        }

        var newRange = CFRange(location: selectedRange.location + (text as NSString).length, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &newRange) {
            _ = AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }

        target.lastRenderedText = text
        capturedInsertionTarget = target
        return true
    }

    private func focusedTextElement() -> AXUIElement? {
        if let targetApplication {
            let appElement = AXUIElementCreateApplication(targetApplication.processIdentifier)
            if let focused = copyFocusedUIElement(from: appElement) {
                return focused
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        return copyFocusedUIElement(from: systemWide)
    }

    private func bestCandidateTextElement() -> AXUIElement? {
        if let focused = resolveWritableTextElement(from: focusedTextElement()) {
            return focused
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let elementAtMouse = copyElement(at: lastTriggerMouseLocation, from: systemWide),
           let resolved = resolveWritableTextElement(from: elementAtMouse) {
            return resolved
        }

        return nil
    }

    private func resolveWritableTextElement(from element: AXUIElement?) -> AXUIElement? {
        var current = element
        var remainingHops = 6

        while let candidate = current, remainingHops > 0 {
            if isWritableTextElement(candidate) {
                return candidate
            }
            current = copyUIElementAttribute(kAXParentAttribute, from: candidate)
            remainingHops -= 1
        }

        return nil
    }

    private func isWritableTextElement(_ element: AXUIElement) -> Bool {
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable)
        guard settableResult == .success, isSettable.boolValue else {
            return false
        }
        return copyStringAttribute(kAXValueAttribute, from: element) != nil
    }

    private func copyFocusedUIElement(from element: AXUIElement) -> AXUIElement? {
        var focusedObject: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard result == .success,
              let focusedObject,
              CFGetTypeID(focusedObject) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(focusedObject, to: AXUIElement.self)
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID()
        else {
            return nil
        }

        return value as? String
    }

    private func copyUIElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElement(at point: NSPoint, from element: AXUIElement) -> AXUIElement? {
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(element, Float(point.x), Float(point.y), &hitElement) == .success else {
            return nil
        }
        return hitElement
    }

    private func copySelectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func validatedRange(_ range: CFRange, in string: NSString) -> CFRange? {
        guard range.location != kCFNotFound,
              range.location >= 0,
              range.length >= 0,
              range.location + range.length <= string.length
        else {
            return nil
        }
        return range
    }
}
