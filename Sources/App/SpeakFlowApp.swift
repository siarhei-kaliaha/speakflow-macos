import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Foundation

final class SpeakFlowApp: NSObject, NSApplicationDelegate {
    private struct CapturedInsertionTarget {
        let element: AXUIElement
        let pid: pid_t
        let originalValue: String
        let originalRange: CFRange
        var lastRenderedText: String
    }

    private let configStore = ConfigStore()
    private lazy var historyStore = HistoryStore(baseDirectory: configStore.supportDirectoryURL)
    private var config = AppConfig.default()
    private var history: [HistoryEntry] = []
    private var stats = UsageStats.empty
    private var realtimeTranscriber: ElevenLabsRealtimeTranscriber?
    private var state: DictationState = .idle {
        didSet {
            Task { @MainActor in
                self.refreshUI()
            }
        }
    }

    private lazy var statusMenuController = StatusMenuController(
        actions: .init(
            toggleRecording: { [weak self] in
                Task { @MainActor in self?.toggleRecording() }
            },
            openControlCenter: { [weak self] in
                Task { @MainActor in self?.openControlCenter() }
            },
            pasteLastResult: { [weak self] in
                Task { @MainActor in self?.pasteLastResult() }
            },
            copyLastResult: { [weak self] in
                Task { @MainActor in self?.copyLastResult() }
            },
            openConfig: { [weak self] in
                Task { @MainActor in self?.openConfig() }
            },
            resetWidgetPosition: { [weak self] in
                Task { @MainActor in self?.resetWidgetPosition() }
            },
            quit: { [weak self] in
                Task { @MainActor in self?.quitApp() }
            }
        )
    )
    private lazy var widgetCoordinator = WidgetWindowCoordinator { [weak self] in
        Task { @MainActor in self?.toggleRecording() }
    }

    private var lastOutputText = ""
    private var lastPasteStatus = "Ready in every app"
    private var targetApplication: NSRunningApplication?
    private var capturedInsertionTarget: CapturedInsertionTarget?
    private var pendingLiveInsertion: DispatchWorkItem?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonHotKeyHandler: EventHandlerRef?
    private var fnListenerProcess: Process?
    private var fnListenerPipe: Pipe?
    private var fnIsDown = false
    private var fnUsedWithAnotherKey = false
    private var suppressNextFnRelease = false
    private var lastTriggerMouseLocation = NSPoint.zero
    private var recordingStartedAt: Date?
    private var controlCenterWindowController: ControlCenterWindowController?
    private var isCapturingHotkey = false
    private var pasteQueue: [String] = []
    private var isPasteInFlight = false

    // MARK: - Diagnostics

    private func debugLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: debugLogPath) {
            if let handle = FileHandle(forWritingAtPath: debugLogPath) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    fputs("SpeakFlow debug log write failed: \(error)\n", stderr)
                }
            }
        } else {
            FileManager.default.createFile(atPath: debugLogPath, contents: data)
        }
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("Application did finish launching")
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = makeApplicationIcon()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        do {
            let created = try configStore.ensureConfigExists()
            config = try configStore.load()
            history = historyStore.loadHistory()
            stats = historyStore.loadStats()
            requestPlatformPermissionsIfNeeded()
            _ = statusMenuController
            widgetCoordinator.rebuild(debugLog: debugLog)
            registerHotKey()
            refreshUI()

            if created || config.resolvedElevenLabsAPIKey() == nil {
                openControlCenter()
            }
        } catch {
            presentError(message: error.localizedDescription)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("Application will terminate")
        NotificationCenter.default.removeObserver(self)
        unregisterHotKey()
        realtimeTranscriber?.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Actions

    @MainActor
    @objc
    private func toggleRecordingFromMenu() {
        toggleRecording()
    }

    @MainActor
    @objc
    private func pasteLastResult() {
        guard !lastOutputText.isEmpty else { return }
        enqueuePaste(lastOutputText)
    }

    @MainActor
    @objc
    private func copyLastResult() {
        guard !lastOutputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastOutputText, forType: .string)
    }

    @MainActor
    @objc
    private func openControlCenter() {
        if controlCenterWindowController == nil {
            let controller = ControlCenterWindowController()
            controller.onBeginHotkeyCapture = { [weak self] in
                self?.beginHotkeyCapture()
            }
            controller.onOpenConfigFile = { [weak self] in
                self?.openConfig()
            }
            controller.onClearHistory = { [weak self] in
                self?.clearHistory()
            }
            controller.onUpdateRealtimeModel = { [weak self] model in
                self?.updateRealtimeModel(model)
            }
            controller.onUpdateBatchModel = { [weak self] model in
                self?.updateBatchModel(model)
            }
            controller.onUpdateCleanupModel = { [weak self] model in
                self?.updateCleanupModel(model)
            }
            controlCenterWindowController = controller
        }

        controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: isCapturingHotkey)
        controlCenterWindowController?.showWindow(nil)
        controlCenterWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    @objc
    private func openConfig() {
        do {
            _ = try configStore.ensureConfigExists()
            NSWorkspace.shared.open(configStore.configURL)
        } catch {
            presentError(message: error.localizedDescription)
        }
    }

    @MainActor
    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Configuration

    @MainActor
    private func updateHotkeyBinding(_ binding: HotkeyBinding) {
        config.hotkeyBinding = binding.rawValue
        do {
            try configStore.save(config)
            registerHotKey()
            refreshUI()
            controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: isCapturingHotkey)
        } catch {
            presentError(message: "Could not save the hotkey setting.\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateRealtimeModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != config.elevenLabsRealtimeModel else { return }
        config.elevenLabsRealtimeModel = trimmed
        persistUpdatedConfig(successMessage: nil)
    }

    @MainActor
    private func updateBatchModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != config.transcriptionModel else { return }
        config.transcriptionModel = trimmed
        persistUpdatedConfig(successMessage: nil)
    }

    @MainActor
    private func updateCleanupModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != config.cleanupModel else { return }
        config.cleanupModel = trimmed
        persistUpdatedConfig(successMessage: nil)
    }

    @MainActor
    private func persistUpdatedConfig(successMessage: String?) {
        do {
            try configStore.save(config)
            refreshUI()
            controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: isCapturingHotkey)
            if let successMessage {
                debugLog(successMessage)
            }
        } catch {
            presentError(message: "Could not save settings.\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func clearHistory() {
        do {
            try historyStore.clearHistory()
            history = []
            controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: isCapturingHotkey)
        } catch {
            presentError(message: "Could not clear history.\n\(error.localizedDescription)")
        }
    }

    // MARK: - Paste Queue

    @MainActor
    private func enqueuePaste(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pasteQueue.append(trimmed)
        processNextPasteIfNeeded()
    }

    @MainActor
    private func processNextPasteIfNeeded() {
        guard !isPasteInFlight, !pasteQueue.isEmpty else { return }
        let next = pasteQueue.removeFirst()
        isPasteInFlight = true
        do {
            try pasteIntoTargetApp(next)
        } catch {
            isPasteInFlight = false
            presentError(message: error.localizedDescription)
            processNextPasteIfNeeded()
        }
    }

    @MainActor
    private func completePasteCycle() {
        isPasteInFlight = false
        processNextPasteIfNeeded()
    }

    // MARK: - Branding

    private func makeApplicationIcon() -> NSImage {
        if let bundled = loadBundledAppIconImage() {
            return bundled
        }
        return makePulseImage(
            size: NSSize(width: 512, height: 512),
            color: NSColor.white.withAlphaComponent(0.96),
            backgroundColor: NSColor(calibratedWhite: 0.08, alpha: 1.0),
            template: false
        )
    }

    // MARK: - Widget And Control Center

    @MainActor
    private func beginHotkeyCapture() {
        isCapturingHotkey = true
        registerHotKey()
        controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: true)
    }

    @MainActor
    private func finishHotkeyCapture(with binding: HotkeyBinding) {
        isCapturingHotkey = false
        updateHotkeyBinding(binding)
    }

    @MainActor
    private func cancelHotkeyCapture() {
        guard isCapturingHotkey else { return }
        isCapturingHotkey = false
        registerHotKey()
        controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: false)
    }

    @MainActor
    @objc
    private func resetWidgetPosition() {
        widgetCoordinator.resetLayout(debugLog: debugLog)
    }

    @MainActor
    @objc
    private func handleScreenParametersChanged() {
        widgetCoordinator.refreshForScreenChanges(debugLog: debugLog)
        refreshUI()
    }

    @MainActor
    private func moveWidgetToPreferredScreen(animated: Bool) {
        widgetCoordinator.moveToPreferredScreen(animated: animated, debugLog: debugLog)
    }

    @MainActor
    private func refreshUI() {
        debugLog("UI refreshed for state=\(String(describing: state)) hotkey=\(config.resolvedHotkeyBinding().rawValue)")
        statusMenuController.update(
            state: state,
            hotkeyDisplayName: config.resolvedHotkeyBinding().displayName,
            hasLastOutput: !lastOutputText.isEmpty
        )

        let widgetState: WidgetContentView.VisualState
        switch state {
        case .idle:
            widgetState = .idle
        case .recording:
            widgetState = .active
        case .transcribing:
            widgetState = .processing
        }
        widgetCoordinator.update(state: widgetState)
    }

    // MARK: - Hotkey Monitoring

    @MainActor
    private func registerHotKey() {
        debugLog("Registering hotkey listeners for binding=\(config.resolvedHotkeyBinding().rawValue)")
        unregisterHotKey()
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        if ensureListenEventPermission(prompt: false) {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleKeyDown(event)
            }
        }

        startFnListener()

        if config.resolvedHotkeyBinding() == .ctrlOptionSpace {
            registerCarbonHotKey()
        }
    }

    @MainActor
    private func unregisterHotKey() {
        debugLog("Unregistering hotkey listeners")
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
        fnIsDown = false
        fnUsedWithAnotherKey = false
        suppressNextFnRelease = false
    }

    @MainActor
    private func startFnListener() {
        stopFnListener()

        let listenerURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/SpeakFlowFnListener")

        guard FileManager.default.isExecutableFile(atPath: listenerURL.path) else {
            debugLog("Fn listener missing at \(listenerURL.path)")
            presentError(message: "SpeakFlow could not start the Fn listener helper.")
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = listenerURL
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.debugLog("Fn listener terminated")
                self?.fnListenerProcess = nil
                self?.fnListenerPipe = nil
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }

            let messages = output
                .split(whereSeparator: \.isNewline)
                .map { String($0) }

            DispatchQueue.main.async {
                for message in messages {
                    self?.handleFnListenerMessage(message)
                }
            }
        }

        do {
            try process.run()
            fnListenerProcess = process
            fnListenerPipe = pipe
            debugLog("Fn listener started pid=\(process.processIdentifier)")
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            debugLog("Fn listener launch failed: \(error.localizedDescription)")
            presentError(message: "SpeakFlow could not launch the Fn listener helper.\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func stopFnListener() {
        fnListenerPipe?.fileHandleForReading.readabilityHandler = nil
        fnListenerPipe = nil
        if let process = fnListenerProcess, process.isRunning {
            process.terminate()
        }
        fnListenerProcess = nil
        debugLog("Fn listener stopped")
    }

    @MainActor
    private func registerCarbonHotKey() {
        let eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let app = Unmanaged<SpeakFlowApp>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                app.toggleRecording()
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

        if registerStatus != noErr {
            if let carbonHotKeyHandler {
                RemoveEventHandler(carbonHotKeyHandler)
                self.carbonHotKeyHandler = nil
            }
        }
    }

    @MainActor
    private func handleFlagsChanged(_ event: NSEvent) {
        if isCapturingHotkey {
            if event.keyCode == UInt16(kVK_RightCommand), event.modifierFlags.contains(.command) {
                debugLog("Captured hotkey via flagsChanged: right_command")
                finishHotkeyCapture(with: .rightCommand)
                return
            }
            if event.keyCode == UInt16(kVK_RightControl), event.modifierFlags.contains(.control) {
                debugLog("Captured hotkey via flagsChanged: right_control")
                finishHotkeyCapture(with: .rightControl)
                return
            }
        }

        let binding = config.resolvedHotkeyBinding()
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

        debugLog("flagsChanged keyCode=\(event.keyCode) isDown=\(isDown) binding=\(binding.rawValue)")

        if isDown && !fnIsDown {
            fnIsDown = true
            fnUsedWithAnotherKey = false
            suppressNextFnRelease = false
            lastTriggerMouseLocation = NSEvent.mouseLocation
            moveWidgetToPreferredScreen(animated: false)
            if state == .idle {
                requestRecordingStart()
            }
            return
        }

        if !isDown && fnIsDown {
            fnIsDown = false
            let shouldStopRecording = state == .recording && !fnUsedWithAnotherKey && !suppressNextFnRelease
            fnUsedWithAnotherKey = false
            suppressNextFnRelease = false

            if shouldStopRecording {
                finishRecordingFromHold()
            }
        }
    }

    @MainActor
    private func handleFnListenerMessage(_ message: String) {
        debugLog("Fn listener message: \(message)")
        if isCapturingHotkey {
            switch message {
            case "FN_DOWN":
                finishHotkeyCapture(with: .fn)
                return
            case "RIGHT_MOD_DOWN:RightCommand":
                finishHotkeyCapture(with: .rightCommand)
                return
            case "RIGHT_MOD_DOWN:RightControl":
                finishHotkeyCapture(with: .rightControl)
                return
            default:
                break
            }
        }

        switch message {
        case "FN_DOWN":
            if config.resolvedHotkeyBinding() == .fn, !fnIsDown {
                fnIsDown = true
                fnUsedWithAnotherKey = false
                suppressNextFnRelease = false
                lastTriggerMouseLocation = NSEvent.mouseLocation
                moveWidgetToPreferredScreen(animated: false)
                if state == .idle {
                    requestRecordingStart()
                }
            }
        case "FN_UP":
            if config.resolvedHotkeyBinding() == .fn, fnIsDown {
                fnIsDown = false
                let shouldStopRecording = state == .recording && !fnUsedWithAnotherKey && !suppressNextFnRelease
                fnUsedWithAnotherKey = false
                suppressNextFnRelease = false
                if shouldStopRecording {
                    finishRecordingFromHold()
                }
            }
        case "RIGHT_MOD_DOWN:RightCommand":
            if config.resolvedHotkeyBinding() == .rightCommand, !fnIsDown {
                fnIsDown = true
                fnUsedWithAnotherKey = false
                suppressNextFnRelease = false
                lastTriggerMouseLocation = NSEvent.mouseLocation
                moveWidgetToPreferredScreen(animated: false)
                if state == .idle {
                    requestRecordingStart()
                }
            }
        case "RIGHT_MOD_UP:RightCommand":
            if config.resolvedHotkeyBinding() == .rightCommand, fnIsDown {
                fnIsDown = false
                let shouldStopRecording = state == .recording && !fnUsedWithAnotherKey && !suppressNextFnRelease
                fnUsedWithAnotherKey = false
                suppressNextFnRelease = false
                if shouldStopRecording {
                    finishRecordingFromHold()
                }
            }
        case "RIGHT_MOD_DOWN:RightControl":
            if config.resolvedHotkeyBinding() == .rightControl, !fnIsDown {
                fnIsDown = true
                fnUsedWithAnotherKey = false
                suppressNextFnRelease = false
                lastTriggerMouseLocation = NSEvent.mouseLocation
                moveWidgetToPreferredScreen(animated: false)
                debugLog("Right Control down accepted; requesting recording start")
                if state == .idle {
                    requestRecordingStart()
                }
            }
        case "RIGHT_MOD_UP:RightControl":
            if config.resolvedHotkeyBinding() == .rightControl, fnIsDown {
                fnIsDown = false
                let shouldStopRecording = state == .recording && !fnUsedWithAnotherKey && !suppressNextFnRelease
                fnUsedWithAnotherKey = false
                suppressNextFnRelease = false
                debugLog("Right Control up accepted; shouldStopRecording=\(shouldStopRecording)")
                if shouldStopRecording {
                    finishRecordingFromHold()
                }
            }
        default:
            break
        }
    }

    @MainActor
    private func handleKeyDown(_ event: NSEvent) {
        if isCapturingHotkey {
            if event.keyCode == UInt16(kVK_Escape) {
                cancelHotkeyCapture()
                return
            }
            if event.keyCode == UInt16(kVK_Space),
               event.modifierFlags.contains(.control),
               event.modifierFlags.contains(.option) {
                finishHotkeyCapture(with: .ctrlOptionSpace)
                return
            }
        }

        guard fnIsDown else {
            return
        }

        fnUsedWithAnotherKey = true
        if state == .recording {
            cancelRecordingFromHold()
        }
    }

    // MARK: - Recording Pipeline

    @MainActor
    private func toggleRecording() {
        switch state {
        case .idle:
            requestRecordingStart()
        case .recording:
            finishRecordingFromHold()
        case .transcribing:
            break
        }
    }

    @MainActor
    private func finishRecordingFromHold() {
        guard state == .recording else { return }
        let recordingDuration = Date().timeIntervalSince(recordingStartedAt ?? Date())
        if recordingDuration < minimumIntentionalRecordingDuration {
            debugLog("Ignoring short recording duration=\(recordingDuration)")
            cancelRecordingFromHold()
            return
        }
        state = .transcribing
        debugLog("Finishing recording from hold")
        let transcriber = realtimeTranscriber
        Task {
            do {
                let transcript = try await transcriber?.finish() ?? ""
                let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTranscript.isEmpty {
                    await MainActor.run {
                        self.debugLog("Transcript was empty after finish; returning to idle without alert")
                        self.realtimeTranscriber = nil
                        self.recordingStartedAt = nil
                        self.state = .idle
                    }
                } else {
                    await applyTranscriptResult(trimmedTranscript)
                }
            } catch {
                if let recoveredTranscript = await self.recoverTranscriptFromFallback(using: transcriber, after: error) {
                    await self.applyTranscriptResult(recoveredTranscript)
                } else if self.shouldSilentlyIgnore(error: error) {
                    await MainActor.run {
                        self.realtimeTranscriber = nil
                        self.recordingStartedAt = nil
                        self.state = .idle
                        self.debugLog("Ignoring non-fatal transcription error: \(error.localizedDescription)")
                    }
                } else {
                    await MainActor.run {
                        self.realtimeTranscriber = nil
                        self.state = .idle
                        self.debugLog("Transcription finish failed: \(error.localizedDescription)")
                        self.presentError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    @MainActor
    private func cancelRecordingFromHold() {
        guard state == .recording else { return }
        realtimeTranscriber?.cancel()
        realtimeTranscriber = nil
        state = .idle
        suppressNextFnRelease = true
        recordingStartedAt = nil
        debugLog("Recording cancelled from hold")
    }

    @MainActor
    private func requestRecordingStart() {
        debugLog("Requesting recording start; microphoneAuth=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    (NSApp.delegate as? SpeakFlowApp)?.handleMicrophonePermissionResult(granted)
                }
            }
        case .denied, .restricted:
            presentError(message: "Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone.")
        @unknown default:
            presentError(message: "Microphone permission is unavailable on this system.")
        }
    }

    @MainActor
    private func handleMicrophonePermissionResult(_ granted: Bool) {
        if granted {
            startRecording()
        } else {
            presentError(message: "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone.")
        }
    }

    @MainActor
    private func startRecording() {
        do {
            config = try configStore.load()
            targetApplication = captureTargetApplication()
            let transcriber = ElevenLabsRealtimeTranscriber(config: config)
            try transcriber.start(previousText: nil)
            realtimeTranscriber = transcriber
            recordingStartedAt = Date()
            state = .recording
            debugLog("Recording started successfully")
        } catch {
            recordingStartedAt = nil
            state = .idle
            debugLog("Recording failed to start: \(error.localizedDescription)")
            presentError(message: error.localizedDescription)
        }
    }

    private func applyTranscriptResult(_ transcript: String) async {
        do {
            config = try configStore.load()
            let client = OpenAICompatibleClient(config: config)
            let finalText = try await client.cleanup(text: transcript)
            await MainActor.run {
                self.realtimeTranscriber = nil
                self.recordingStartedAt = nil
                self.lastOutputText = finalText
                if let snapshot = try? self.historyStore.append(text: finalText, provider: self.config.providerName) {
                    self.history = snapshot.0
                    self.stats = snapshot.1
                }
                self.enqueuePaste(finalText)
                self.controlCenterWindowController?.update(
                    config: self.config,
                    history: self.history,
                    stats: self.stats,
                    isCapturingHotkey: self.isCapturingHotkey
                )
                self.state = .idle
            }
        } catch {
            await MainActor.run {
                self.realtimeTranscriber = nil
                self.recordingStartedAt = nil
                self.state = .idle
                self.presentError(message: error.localizedDescription)
            }
        }
    }

    private func recoverTranscriptFromFallback(using transcriber: ElevenLabsRealtimeTranscriber?, after error: Error) async -> String? {
        guard let transcriber,
              let wavData = transcriber.fallbackWAVData(),
              !wavData.isEmpty else {
            return nil
        }

        await MainActor.run {
            self.debugLog("Realtime transcription failed; attempting ElevenLabs batch fallback: \(error.localizedDescription)")
        }

        do {
            let fallbackClient = ElevenLabsBatchTranscriberClient(config: config)
            let transcript = try await fallbackClient.transcribe(audioData: wavData)
            await MainActor.run {
                self.debugLog("ElevenLabs batch fallback succeeded")
            }
            return transcript
        } catch {
            await MainActor.run {
                self.debugLog("ElevenLabs batch fallback failed: \(error.localizedDescription)")
            }
            return nil
        }
    }

    private func shouldSilentlyIgnore(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let silentMarkers = [
            "no transcript arrived",
            "returned an empty transcript",
            "empty transcript",
            "transcript was empty"
        ]
        return silentMarkers.contains { message.contains($0) }
    }

    // MARK: - Target App Interaction

    private func captureTargetApplication() -> NSRunningApplication? {
        let currentAppPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.processIdentifier != currentAppPID else {
            return nil
        }
        return frontmost
    }

    @MainActor
    private func captureInsertionTarget() -> CapturedInsertionTarget? {
        guard ensureAccessibilityPermission(prompt: false),
              let focusedElement = bestCandidateTextElement()
        else {
            return nil
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &pid) == .success,
              let currentValue = copyStringAttribute(kAXValueAttribute, from: focusedElement)
        else {
            return nil
        }

        let currentNSString = currentValue as NSString
        let selectedRange = copySelectedRange(from: focusedElement) ?? CFRange(location: currentNSString.length, length: 0)
        guard validatedRange(selectedRange, in: currentNSString) != nil else {
            return nil
        }

        return CapturedInsertionTarget(
            element: focusedElement,
            pid: pid,
            originalValue: currentValue,
            originalRange: selectedRange,
            lastRenderedText: ""
        )
    }

    @MainActor
    private func scheduleLiveInsertion(for transcript: String) {
        guard state == .recording, config.preferAccessibilityInsertion else {
            return
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        pendingLiveInsertion?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.state == .recording else { return }
            if self.renderCapturedInsertion(trimmed) {
                self.lastPasteStatus = "Live insertion via Accessibility"
            }
        }
        pendingLiveInsertion = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    @MainActor
    private func pasteIntoTargetApp(_ text: String) throws {
        debugLog("Paste requested for textLength=\((text as NSString).length)")
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let hasAccessibility = ensureAccessibilityPermission(prompt: false)
        if !hasAccessibility {
            _ = ensureAccessibilityPermission(prompt: true)
            lastPasteStatus = "Clipboard only · Accessibility permission missing"
            refreshUI()
            debugLog("Paste fell back to clipboard only because accessibility is missing")
            completePasteCycle()
            return
        }

        let visibleWidgets = widgetCoordinator.hideVisibleWindows()

        if let targetApplication {
            targetApplication.activate(options: [])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [restoreClipboard = config.restoreClipboard] in
            let pasted = self.performMacPaste()
            self.lastPasteStatus = pasted ? "Clipboard paste" : "Clipboard only"
            self.refreshUI()
            self.debugLog("Paste attempt finished pasted=\(pasted)")

            if restoreClipboard {
                let restoreDelay = pasted ? 1.0 : 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    snapshot.restore(to: pasteboard)
                }
            }

            if !visibleWidgets.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    self.widgetCoordinator.restoreWindows(visibleWidgets)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.completePasteCycle()
            }
        }
    }

    @MainActor
    private func performMacPaste() -> Bool {
        if ensurePostEventPermission(prompt: false) {
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

    @MainActor
    private func insertTextViaAccessibility(_ text: String) -> Bool {
        guard let focusedElement = focusedTextElement() else {
            return false
        }
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(focusedElement, kAXValueAttribute as CFString, &isSettable)
        guard settableResult == .success, isSettable.boolValue else {
            return false
        }

        guard let currentValue = copyStringAttribute(kAXValueAttribute, from: focusedElement) else {
            return false
        }

        let currentNSString = currentValue as NSString
        let selectedRange = copySelectedRange(from: focusedElement) ?? CFRange(location: currentNSString.length, length: 0)
        guard selectedRange.location != kCFNotFound,
              selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= currentNSString.length
        else {
            return false
        }

        let replacement = currentNSString.replacingCharacters(in: NSRange(location: selectedRange.location, length: selectedRange.length), with: text)
        let setValueResult = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, replacement as CFTypeRef)
        guard setValueResult == .success else {
            return false
        }

        var newRange = CFRange(location: selectedRange.location + (text as NSString).length, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &newRange) else {
            return true
        }

        _ = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        return true
    }

    @MainActor
    private func renderCapturedInsertion(_ text: String) -> Bool {
        guard var target = capturedInsertionTarget else {
            return false
        }

        let originalNSString = target.originalValue as NSString
        guard let selectedRange = validatedRange(target.originalRange, in: originalNSString) else {
            return false
        }

        let replacement = originalNSString.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: text
        )
        let setValueResult = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, replacement as CFTypeRef)
        guard setValueResult == .success else {
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

    @MainActor
    private func restoreCapturedInsertionTargetIfNeeded() {
        guard var target = capturedInsertionTarget, !target.lastRenderedText.isEmpty else {
            return
        }

        let setValueResult = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, target.originalValue as CFTypeRef)
        guard setValueResult == .success else {
            return
        }

        var originalRange = target.originalRange
        if let rangeValue = AXValueCreate(.cfRange, &originalRange) {
            _ = AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        target.lastRenderedText = ""
        capturedInsertionTarget = target
    }

    // MARK: - Accessibility Helpers

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

    @MainActor
    private func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    private func ensurePostEventPermission(prompt: Bool) -> Bool {
        if CGPreflightPostEventAccess() {
            return true
        }
        guard prompt else {
            return false
        }
        return CGRequestPostEventAccess()
    }

    @MainActor
    private func ensureListenEventPermission(prompt: Bool) -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        guard prompt else {
            return false
        }
        return CGRequestListenEventAccess()
    }

    @MainActor
    private func requestPlatformPermissionsIfNeeded() {
        _ = ensureAccessibilityPermission(prompt: false)
        _ = ensureListenEventPermission(prompt: false)
        _ = ensurePostEventPermission(prompt: false)
    }

    // MARK: - Error Presentation

    @MainActor
    private func presentError(message: String) {
        let sanitizedMessage = message.replacingOccurrences(of: "\n", with: " | ")
        debugLog("Presenting error: \(sanitizedMessage)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appDisplayName
        alert.informativeText = message
        alert.runModal()
    }
}
