import AppKit
import Carbon
import Foundation

@MainActor
final class HotkeyMonitor {
    enum Event {
        case toggleRecording
        case requestRecordingStart(triggerLocation: NSPoint)
        case requestRecordingStop
        case requestRecordingCancel
        case capturedBinding(HotkeyBinding)
    }

    var onEvent: ((Event) -> Void)?
    var onDebugLog: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onMoveWidgetToPreferredScreen: (() -> Void)?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonHotKeyHandler: EventHandlerRef?
    private var fnListenerProcess: Process?
    private var fnListenerPipe: Pipe?
    private var holdKeyIsDown = false
    private var holdKeyUsedWithAnotherKey = false
    private var suppressNextHoldRelease = false

    func register(binding: HotkeyBinding, isCapturingHotkey: Bool) {
        onDebugLog?("Registering hotkey listeners for binding=\(binding.rawValue)")
        unregister()

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event, binding: binding, isCapturingHotkey: isCapturingHotkey)
            return event
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event, isCapturingHotkey: isCapturingHotkey)
            return event
        }

        if PlatformPermissions.listenEvent(prompt: false) {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                self?.handleFlagsChanged(event, binding: binding, isCapturingHotkey: isCapturingHotkey)
            }
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleKeyDown(event, isCapturingHotkey: isCapturingHotkey)
            }
        }

        startFnListener(binding: binding, isCapturingHotkey: isCapturingHotkey)

        if binding == .ctrlOptionSpace {
            registerCarbonHotKey()
        }
    }

    func unregister() {
        onDebugLog?("Unregistering hotkey listeners")
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
        if let carbonHotKeyRef {
            UnregisterEventHotKey(carbonHotKeyRef)
            self.carbonHotKeyRef = nil
        }
        if let carbonHotKeyHandler {
            RemoveEventHandler(carbonHotKeyHandler)
            self.carbonHotKeyHandler = nil
        }

        stopFnListener()
        holdKeyIsDown = false
        holdKeyUsedWithAnotherKey = false
        suppressNextHoldRelease = false
    }

    func cancelCurrentHold() {
        suppressNextHoldRelease = true
        holdKeyUsedWithAnotherKey = true
    }

    private func registerCarbonHotKey() {
        let eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                monitor.onEvent?(.toggleRecording)
            }
            return noErr
        }

        let installStatus = eventTypes.withUnsafeBufferPointer { buffer -> OSStatus in
            InstallEventHandler(
                GetApplicationEventTarget(),
                callback,
                1,
                buffer.baseAddress,
                userData,
                &self.carbonHotKeyHandler
            )
        }
        guard installStatus == noErr else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5350464C), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )

        if registerStatus != noErr, let carbonHotKeyHandler {
            RemoveEventHandler(carbonHotKeyHandler)
            self.carbonHotKeyHandler = nil
        }
    }

    private func startFnListener(binding: HotkeyBinding, isCapturingHotkey: Bool) {
        stopFnListener()

        let listenerURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SpeakFlowFnListener")
        guard FileManager.default.isExecutableFile(atPath: listenerURL.path) else {
            onDebugLog?("Fn listener missing at \(listenerURL.path)")
            onError?("SpeakFlow could not start the Fn listener helper.")
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = listenerURL
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.onDebugLog?("Fn listener terminated")
                self?.fnListenerProcess = nil
                self?.fnListenerPipe = nil
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }

            let messages = output.split(whereSeparator: \.isNewline).map(String.init)
            DispatchQueue.main.async {
                messages.forEach { self?.handleFnListenerMessage($0, binding: binding, isCapturingHotkey: isCapturingHotkey) }
            }
        }

        do {
            try process.run()
            fnListenerProcess = process
            fnListenerPipe = pipe
            onDebugLog?("Fn listener started pid=\(process.processIdentifier)")
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            onDebugLog?("Fn listener launch failed: \(error.localizedDescription)")
            onError?("SpeakFlow could not launch the Fn listener helper.\n\(error.localizedDescription)")
        }
    }

    private func stopFnListener() {
        fnListenerPipe?.fileHandleForReading.readabilityHandler = nil
        fnListenerPipe = nil
        if let process = fnListenerProcess, process.isRunning {
            process.terminate()
        }
        fnListenerProcess = nil
        onDebugLog?("Fn listener stopped")
    }

    private func handleFlagsChanged(_ event: NSEvent, binding: HotkeyBinding, isCapturingHotkey: Bool) {
        if isCapturingHotkey {
            if event.keyCode == UInt16(kVK_RightCommand), event.modifierFlags.contains(.command) {
                onDebugLog?("Captured hotkey via flagsChanged: right_command")
                onEvent?(.capturedBinding(.rightCommand))
                return
            }
            if event.keyCode == UInt16(kVK_RightControl), event.modifierFlags.contains(.control) {
                onDebugLog?("Captured hotkey via flagsChanged: right_control")
                onEvent?(.capturedBinding(.rightControl))
                return
            }
        }

        let isDown: Bool
        switch binding {
        case .rightCommand:
            guard event.keyCode == UInt16(kVK_RightCommand) else { return }
            isDown = event.modifierFlags.contains(.command)
        case .rightControl:
            guard event.keyCode == UInt16(kVK_RightControl) else { return }
            isDown = event.modifierFlags.contains(.control)
        default:
            return
        }

        onDebugLog?("flagsChanged keyCode=\(event.keyCode) isDown=\(isDown) binding=\(binding.rawValue)")
        handleHoldTransition(isDown: isDown)
    }

    private func handleFnListenerMessage(_ message: String, binding: HotkeyBinding, isCapturingHotkey: Bool) {
        onDebugLog?("Fn listener message: \(message)")

        if isCapturingHotkey {
            switch message {
            case "FN_DOWN":
                onEvent?(.capturedBinding(.fn))
                return
            case "RIGHT_MOD_DOWN:RightCommand":
                onEvent?(.capturedBinding(.rightCommand))
                return
            case "RIGHT_MOD_DOWN:RightControl":
                onEvent?(.capturedBinding(.rightControl))
                return
            default:
                break
            }
        }

        switch message {
        case "FN_DOWN" where binding == .fn:
            handleHoldTransition(isDown: true)
        case "FN_UP" where binding == .fn:
            handleHoldTransition(isDown: false)
        case "RIGHT_MOD_DOWN:RightCommand" where binding == .rightCommand:
            handleHoldTransition(isDown: true)
        case "RIGHT_MOD_UP:RightCommand" where binding == .rightCommand:
            handleHoldTransition(isDown: false)
        case "RIGHT_MOD_DOWN:RightControl" where binding == .rightControl:
            onDebugLog?("Right Control down accepted; requesting recording start")
            handleHoldTransition(isDown: true)
        case "RIGHT_MOD_UP:RightControl" where binding == .rightControl:
            let shouldStopRecording = holdKeyIsDown && !holdKeyUsedWithAnotherKey && !suppressNextHoldRelease
            onDebugLog?("Right Control up accepted; shouldStopRecording=\(shouldStopRecording)")
            handleHoldTransition(isDown: false)
        default:
            break
        }
    }

    private func handleKeyDown(_ event: NSEvent, isCapturingHotkey: Bool) {
        if isCapturingHotkey {
            if event.keyCode == UInt16(kVK_Escape) {
                return
            }
            if event.keyCode == UInt16(kVK_Space),
               event.modifierFlags.contains(.control),
               event.modifierFlags.contains(.option) {
                onEvent?(.capturedBinding(.ctrlOptionSpace))
                return
            }
        }

        guard holdKeyIsDown else { return }
        holdKeyUsedWithAnotherKey = true
        onEvent?(.requestRecordingCancel)
    }

    private func handleHoldTransition(isDown: Bool) {
        if isDown && !holdKeyIsDown {
            holdKeyIsDown = true
            holdKeyUsedWithAnotherKey = false
            suppressNextHoldRelease = false
            let triggerLocation = NSEvent.mouseLocation
            onMoveWidgetToPreferredScreen?()
            onEvent?(.requestRecordingStart(triggerLocation: triggerLocation))
            return
        }

        if !isDown && holdKeyIsDown {
            holdKeyIsDown = false
            let shouldStopRecording = !holdKeyUsedWithAnotherKey && !suppressNextHoldRelease
            holdKeyUsedWithAnotherKey = false
            suppressNextHoldRelease = false
            if shouldStopRecording {
                onEvent?(.requestRecordingStop)
            }
        }
    }
}
