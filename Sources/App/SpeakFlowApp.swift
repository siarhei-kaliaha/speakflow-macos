import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Foundation

final class SpeakFlowApp: NSObject, NSApplicationDelegate {
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
    @MainActor private lazy var hotkeyMonitor = makeHotkeyMonitor()
    @MainActor private lazy var textInsertionController = TextInsertionController(debugLog: debugLog)

    private var lastOutputText = ""
    private var lastPasteStatus = "Ready in every app"
    private var recordingStartedAt: Date?
    private var lastRecordingDuration: TimeInterval?
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

    @MainActor
    private func makeHotkeyMonitor() -> HotkeyMonitor {
        let monitor = HotkeyMonitor()
        monitor.onDebugLog = { [weak self] message in
            self?.debugLog(message)
        }
        monitor.onError = { [weak self] message in
            Task { @MainActor in
                self?.presentError(message: message)
            }
        }
        monitor.onMoveWidgetToPreferredScreen = { [weak self] in
            Task { @MainActor in
                self?.moveWidgetToPreferredScreen(animated: false)
            }
        }
        monitor.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHotkeyMonitorEvent(event)
            }
        }
        return monitor
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
        textInsertionController.paste(
            text: next,
            restoreClipboard: config.restoreClipboard,
            hideWidgets: { self.widgetCoordinator.hideVisibleWindows() },
            restoreWidgets: { windows in
                self.widgetCoordinator.restoreWindows(windows.compactMap { $0 as? WidgetPanel })
            },
            statusHandler: { status in
                self.lastPasteStatus = status
                self.refreshUI()
            },
            completion: {
                self.completePasteCycle()
            }
        )
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
            widgetCoordinator.updateAudioLevels(Array(repeating: 0, count: 25))
            widgetCoordinator.updateTimer(startDate: nil, frozenDuration: nil)
        case .recording:
            widgetState = .active
            widgetCoordinator.updateTimer(startDate: recordingStartedAt, frozenDuration: nil)
        case .transcribing:
            widgetState = .processing
            widgetCoordinator.updateAudioLevels(Array(repeating: 0, count: 25))
            widgetCoordinator.updateTimer(startDate: nil, frozenDuration: lastRecordingDuration)
        }
        widgetCoordinator.update(state: widgetState)
    }

    // MARK: - Hotkey Monitoring

    @MainActor
    private func handleHotkeyMonitorEvent(_ event: HotkeyMonitor.Event) {
        switch event {
        case .toggleRecording:
            toggleRecording()
        case .requestRecordingStart(let triggerLocation):
            textInsertionController.updateTriggerLocation(triggerLocation)
            if state == .idle {
                requestRecordingStart()
            }
        case .requestRecordingStop:
            if state == .recording {
                finishRecordingFromHold()
            }
        case .requestRecordingCancel:
            if state == .recording {
                cancelRecordingFromHold()
            }
        case .cancelHotkeyCapture:
            cancelHotkeyCapture()
        case .capturedBinding(let binding):
            finishHotkeyCapture(with: binding)
        }
    }

    @MainActor
    private func registerHotKey() {
        hotkeyMonitor.register(binding: config.resolvedHotkeyBinding(), isCapturingHotkey: isCapturingHotkey)
    }

    @MainActor
    private func unregisterHotKey() {
        hotkeyMonitor.unregister()
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
        lastRecordingDuration = recordingDuration
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
                        self.lastRecordingDuration = nil
                        self.textInsertionController.clearTransientState()
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
                        self.lastRecordingDuration = nil
                        self.textInsertionController.clearTransientState()
                        self.state = .idle
                        self.debugLog("Ignoring non-fatal transcription error: \(error.localizedDescription)")
                    }
                } else {
                    await MainActor.run {
                        self.realtimeTranscriber = nil
                        self.textInsertionController.clearTransientState()
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
        textInsertionController.clearTransientState()
        hotkeyMonitor.cancelCurrentHold()
        state = .idle
        recordingStartedAt = nil
        lastRecordingDuration = nil
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
            textInsertionController.captureTargetApplication()
            textInsertionController.prepareForRecording(preferAccessibilityInsertion: config.preferAccessibilityInsertion)
            let transcriber = ElevenLabsRealtimeTranscriber(config: config)
            transcriber.onAudioLevelsChanged = { [weak self] levels in
                Task { @MainActor in
                    guard let self, self.state == .recording else { return }
                    self.widgetCoordinator.updateAudioLevels(levels)
                }
            }
            try transcriber.start(previousText: nil)
            realtimeTranscriber = transcriber
            recordingStartedAt = Date()
            lastRecordingDuration = nil
            state = .recording
            debugLog("Recording started successfully")
        } catch {
            recordingStartedAt = nil
            lastRecordingDuration = nil
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
                self.lastRecordingDuration = nil
                self.textInsertionController.clearTransientState()
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
                self.lastRecordingDuration = nil
                self.textInsertionController.clearTransientState()
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

    @MainActor
    private func requestPlatformPermissionsIfNeeded() {
        textInsertionController.requestPlatformPermissionsIfNeeded()
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
