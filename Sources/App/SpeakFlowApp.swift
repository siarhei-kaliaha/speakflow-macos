import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Foundation
import UserNotifications

final class SpeakFlowApp: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private lazy var captureStore = CaptureStore(baseDirectory: configStore.supportDirectoryURL)
    private var config = AppConfig.default()
    private var captures: [CaptureRecord] = []
    private var stats = UsageStats.empty
    private var realtimeTranscriber: ElevenLabsRealtimeTranscriber?
    private let recorderController = RecorderController()
    @MainActor private lazy var meetingDetectionService = makeMeetingDetectionService()
    @MainActor private lazy var captureNotificationService = makeCaptureNotificationService()
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
    private lazy var widgetCoordinator = WidgetWindowCoordinator(
        onPrimaryClick: { [weak self] in
            Task { @MainActor in self?.handleWidgetPrimaryAction() }
        },
        onStopClick: { [weak self] in
            Task { @MainActor in self?.finishRecordingFromHold() }
        },
        onDismissMeeting: { [weak self] in
            Task { @MainActor in self?.dismissMeetingPrompt() }
        },
        onAcceptMeeting: { [weak self] in
            Task { @MainActor in self?.acceptMeetingPrompt() }
        },
        initialWidgetPositionsByScreen: config.widgetPositionsByScreen,
        onWidgetPositionsChanged: { [weak self] positionsByScreen in
            Task { @MainActor in
                self?.persistWidgetPositions(positionsByScreen)
            }
        }
    )
    @MainActor private lazy var hotkeyMonitor = makeHotkeyMonitor()
    @MainActor private lazy var textInsertionController = TextInsertionController(debugLog: debugLog)

    private var lastOutputText = ""
    private var lastPasteStatus = "Ready in every app"
    private var recordingStartedAt: Date?
    private var lastRecordingDuration: TimeInterval?
    private var activeCaptureMode: CaptureMode?
    private var pendingCaptureMode: CaptureMode?
    private var controlCenterWindowController: ControlCenterWindowController?
    private var isCapturingHotkey = false
    private var pasteQueue: [String] = []
    private var isPasteInFlight = false
    private var summarizingCaptureID: UUID?
    private var visibleMeetingPrompt: MeetingSessionCandidate?
    private var queuedMeetingCandidate: MeetingSessionCandidate?
    private var pendingMeetingRecordingCandidate: MeetingSessionCandidate?
    private var isPresentingErrorAlert = false
    private let transcriptionTimeoutSeconds: TimeInterval = 60
    private let cleanupTimeoutSeconds: TimeInterval = 25

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

    @MainActor
    private func makeMeetingDetectionService() -> MeetingDetectionService {
        let service = MeetingDetectionService(debugLog: debugLog)
        service.onMeetingDetected = { [weak self] candidate in
            Task { @MainActor in
                self?.handleMeetingDetected(candidate)
            }
        }
        service.onMeetingEnded = { [weak self] in
            Task { @MainActor in
                self?.handleMeetingEnded()
            }
        }
        return service
    }

    @MainActor
    private func makeCaptureNotificationService() -> CaptureNotificationService {
        let service = CaptureNotificationService(debugLog: debugLog)
        service.onOpenRecordingCapture = { [weak self] captureID in
            Task { @MainActor in
                self?.openRecordingsWorkspace(selectedCaptureID: captureID)
            }
        }
        return service
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
            captures = captureStore.loadCaptures()
            stats = captureStore.loadStats()
            let forceOpenControlCenter = ProcessInfo.processInfo.environment["SPEAKFLOW_OPEN_CONTROL_CENTER"] == "1"
            requestPlatformPermissionsIfNeeded()
            captureNotificationService.configure()
            _ = statusMenuController
            widgetCoordinator.rebuild(debugLog: debugLog)
            registerHotKey()
            meetingDetectionService.start()
            refreshUI()

            if created || config.resolvedElevenLabsAPIKey() == nil || forceOpenControlCenter {
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
        meetingDetectionService.stop()
        realtimeTranscriber?.cancel()
        recorderController.cancel()
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
                self?.clearCaptures()
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
            controller.onSummarizeCapture = { [weak self] captureID in
                self?.summarizeCapture(withID: captureID)
            }
            controlCenterWindowController = controller
        }

        controlCenterWindowController?.update(
            config: config,
            captures: captures,
            stats: stats,
            isCapturingHotkey: isCapturingHotkey,
            activeCaptureMode: activeCaptureMode,
            summarizingCaptureID: summarizingCaptureID
        )
        controlCenterWindowController?.showWindow(nil)
        controlCenterWindowController?.present(page: .dictation)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func openRecordingsWorkspace(selectedCaptureID: UUID?) {
        if controlCenterWindowController == nil {
            openControlCenter()
        } else {
            controlCenterWindowController?.update(
                config: config,
                captures: captures,
                stats: stats,
                isCapturingHotkey: isCapturingHotkey,
                activeCaptureMode: activeCaptureMode,
                summarizingCaptureID: summarizingCaptureID
            )
        }
        controlCenterWindowController?.showWindow(nil)
        controlCenterWindowController?.present(page: .recordings, selectedRecordingCaptureID: selectedCaptureID)
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
            controlCenterWindowController?.update(
                config: config,
                captures: captures,
                stats: stats,
                isCapturingHotkey: isCapturingHotkey,
                activeCaptureMode: activeCaptureMode,
                summarizingCaptureID: summarizingCaptureID
            )
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
            controlCenterWindowController?.update(
                config: config,
                captures: captures,
                stats: stats,
                isCapturingHotkey: isCapturingHotkey,
                activeCaptureMode: activeCaptureMode,
                summarizingCaptureID: summarizingCaptureID
            )
            if let successMessage {
                debugLog(successMessage)
            }
        } catch {
            presentError(message: "Could not save settings.\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func clearCaptures() {
        do {
            try captureStore.clearCaptures()
            captures = []
            stats = .empty
            controlCenterWindowController?.update(
                config: config,
                captures: captures,
                stats: stats,
                isCapturingHotkey: isCapturingHotkey,
                activeCaptureMode: activeCaptureMode,
                summarizingCaptureID: summarizingCaptureID
            )
        } catch {
            presentError(message: "Could not clear the library.\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func summarizeCapture(withID captureID: UUID) {
        guard summarizingCaptureID == nil,
              let capture = captures.first(where: { $0.id == captureID && $0.kind == .recordingSession }) else {
            return
        }

        summarizingCaptureID = captureID
        controlCenterWindowController?.update(
            config: config,
            captures: captures,
            stats: stats,
            isCapturingHotkey: isCapturingHotkey,
            activeCaptureMode: activeCaptureMode,
            summarizingCaptureID: summarizingCaptureID
        )

        Task {
            do {
                config = try configStore.load()
                let client = OpenAICompatibleClient(config: config)
                let summary = try await client.summarize(text: capture.finalText)
                await MainActor.run {
                    if let snapshot = try? self.captureStore.updateSummary(for: captureID, summary: summary) {
                        self.captures = snapshot.0
                        self.stats = snapshot.1
                    }
                    self.summarizingCaptureID = nil
                    self.controlCenterWindowController?.update(
                        config: self.config,
                        captures: self.captures,
                        stats: self.stats,
                        isCapturingHotkey: self.isCapturingHotkey,
                        activeCaptureMode: self.activeCaptureMode,
                        summarizingCaptureID: self.summarizingCaptureID
                    )
                }
            } catch {
                await MainActor.run {
                    self.summarizingCaptureID = nil
                    self.controlCenterWindowController?.update(
                        config: self.config,
                        captures: self.captures,
                        stats: self.stats,
                        isCapturingHotkey: self.isCapturingHotkey,
                        activeCaptureMode: self.activeCaptureMode,
                        summarizingCaptureID: self.summarizingCaptureID
                    )
                    self.presentError(message: "Could not summarize this recording.\n\(error.localizedDescription)")
                }
            }
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
        controlCenterWindowController?.update(
            config: config,
            captures: captures,
            stats: stats,
            isCapturingHotkey: true,
            activeCaptureMode: activeCaptureMode,
            summarizingCaptureID: summarizingCaptureID
        )
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
        controlCenterWindowController?.update(
            config: config,
            captures: captures,
            stats: stats,
            isCapturingHotkey: false,
            activeCaptureMode: activeCaptureMode,
            summarizingCaptureID: summarizingCaptureID
        )
    }

    @MainActor
    @objc
    private func resetWidgetPosition() {
        widgetCoordinator.resetLayout(debugLog: debugLog)
    }

    @MainActor
    private func persistWidgetPositions(_ positionsByScreen: [String: WidgetScreenPosition]) {
        config.widgetPositionsByScreen = positionsByScreen
        do {
            try configStore.save(config)
            debugLog("Persisted widget positions for \(positionsByScreen.count) screen(s)")
        } catch {
            debugLog("Failed to persist widget positions: \(error.localizedDescription)")
        }
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
        if state == .idle, visibleMeetingPrompt == nil, let queuedMeetingCandidate {
            visibleMeetingPrompt = queuedMeetingCandidate
            self.queuedMeetingCandidate = nil
            debugLog("Promoted queued meeting prompt signature=\(queuedMeetingCandidate.signature)")
        }
        statusMenuController.update(
            state: state,
            hotkeyDisplayName: config.resolvedHotkeyBinding().displayName,
            hasLastOutput: !lastOutputText.isEmpty
        )

        let widgetState: WidgetContentView.VisualState
        switch state {
        case .idle:
            if let visibleMeetingPrompt {
                debugLog("Rendering meeting prompt for signature=\(visibleMeetingPrompt.signature)")
                widgetState = .meetingDetected
                widgetCoordinator.updateMeetingPrompt(appName: visibleMeetingPrompt.app.displayName)
                widgetCoordinator.updateAudioLevels(Array(repeating: 0, count: 25))
                widgetCoordinator.updateTimer(startDate: nil, frozenDuration: nil)
            } else {
                widgetState = .idle
                widgetCoordinator.updateMeetingPrompt(appName: nil)
                widgetCoordinator.updateAudioLevels(Array(repeating: 0, count: 25))
                widgetCoordinator.updateTimer(startDate: nil, frozenDuration: nil)
            }
        case .recording:
            widgetState = activeCaptureMode == .recording ? .recordingActive : .dictationActive
            widgetCoordinator.updateMeetingPrompt(appName: nil)
            widgetCoordinator.updateTimer(startDate: recordingStartedAt, frozenDuration: nil)
        case .transcribing:
            widgetState = activeCaptureMode == .recording ? .processingRecording : .processingDictation
            widgetCoordinator.updateMeetingPrompt(appName: nil)
            widgetCoordinator.updateAudioLevels(Array(repeating: 0, count: 25))
            widgetCoordinator.updateTimer(startDate: nil, frozenDuration: lastRecordingDuration)
        }
        widgetCoordinator.update(state: widgetState)
    }

    @MainActor
    private func handleMeetingDetected(_ candidate: MeetingSessionCandidate) {
        guard state != .recording, state != .transcribing else {
            queuedMeetingCandidate = candidate
            debugLog("Queued meeting prompt while busy for \(candidate.app.displayName)")
            return
        }
        debugLog("Showing meeting prompt immediately for signature=\(candidate.signature)")
        visibleMeetingPrompt = candidate
        queuedMeetingCandidate = nil
        refreshUI()
    }

    @MainActor
    private func handleMeetingEnded() {
        debugLog("Meeting ended for visible=\(visibleMeetingPrompt?.signature ?? "none") queued=\(queuedMeetingCandidate?.signature ?? "none")")
        visibleMeetingPrompt = nil
        queuedMeetingCandidate = nil
        if state == .idle {
            refreshUI()
        }
    }

    @MainActor
    private func dismissMeetingPrompt() {
        debugLog("Dismissing meeting prompt visible=\(visibleMeetingPrompt?.signature ?? "none") queued=\(queuedMeetingCandidate?.signature ?? "none")")
        visibleMeetingPrompt = nil
        queuedMeetingCandidate = nil
        meetingDetectionService.dismissCurrentMeetingPrompt()
        refreshUI()
    }

    @MainActor
    private func acceptMeetingPrompt() {
        let candidate = visibleMeetingPrompt ?? queuedMeetingCandidate
        debugLog("Accepting meeting prompt signature=\(candidate?.signature ?? "none")")
        visibleMeetingPrompt = nil
        queuedMeetingCandidate = nil
        meetingDetectionService.dismissCurrentMeetingPrompt()
        requestRecordingStart(mode: .recording, meetingCandidate: candidate)
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
                requestRecordingStart(mode: .dictation)
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
            requestRecordingStart(mode: .dictation)
        case .recording:
            finishRecordingFromHold()
        case .transcribing:
            break
        }
    }

    @MainActor
    private func handleWidgetPrimaryAction() {
        switch state {
        case .idle:
            requestRecordingStart(mode: .recording)
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
        Task {
            let captureMode = await MainActor.run { self.activeCaptureMode ?? .dictation }
            let captureStartedAt = await MainActor.run { self.recordingStartedAt ?? Date() }
            let localAudioFileURL = await self.stopLocalRecordingIfNeeded()
            var transcriptionSucceeded = false
            var preservedRecordingURL: URL?
            transcriberCancelAndClear()
            do {
                guard let localAudioFileURL else {
                    throw SpeakFlowError.noRecordedFile
                }

                let transcript = try await self.transcribeRecording(at: localAudioFileURL)
                let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTranscript.isEmpty {
                    await MainActor.run {
                        self.debugLog("Transcript was empty after finish; returning to idle without alert")
                        self.realtimeTranscriber = nil
                        self.recordingStartedAt = nil
                        self.lastRecordingDuration = nil
                        self.pendingMeetingRecordingCandidate = nil
                        self.textInsertionController.clearTransientState()
                        self.activeCaptureMode = nil
                        self.state = .idle
                    }
                } else {
                    transcriptionSucceeded = true
                    switch captureMode {
                    case .dictation:
                        await applyDictationResult(
                            rawTranscript: trimmedTranscript,
                            startedAt: captureStartedAt,
                            duration: recordingDuration
                        )
                    case .recording:
                        await applyRecordingResult(
                            transcript: trimmedTranscript,
                            startedAt: captureStartedAt,
                            duration: recordingDuration
                        )
                    }
                }
            } catch {
                if self.shouldSilentlyIgnore(error: error) {
                    if let localAudioFileURL {
                        preservedRecordingURL = self.preserveRecordingForRecovery(localAudioFileURL)
                    }
                    await MainActor.run {
                        self.realtimeTranscriber = nil
                        self.recordingStartedAt = nil
                        self.lastRecordingDuration = nil
                        self.pendingMeetingRecordingCandidate = nil
                        self.textInsertionController.clearTransientState()
                        self.activeCaptureMode = nil
                        self.state = .idle
                        self.debugLog("Ignoring non-fatal transcription error: \(error.localizedDescription)")
                    }
                } else {
                    if let localAudioFileURL {
                        preservedRecordingURL = self.preserveRecordingForRecovery(localAudioFileURL)
                    }
                    await MainActor.run {
                        self.realtimeTranscriber = nil
                        self.recordingStartedAt = nil
                        self.lastRecordingDuration = nil
                        self.pendingMeetingRecordingCandidate = nil
                        self.textInsertionController.clearTransientState()
                        self.activeCaptureMode = nil
                        self.state = .idle
                        self.debugLog("Transcription finish failed: \(error.localizedDescription)")
                        self.presentError(
                            message: self.userFacingTranscriptionFailureMessage(
                                for: error,
                                preservedRecordingURL: preservedRecordingURL
                            )
                        )
                    }
                }
            }
            if let localAudioFileURL {
                if transcriptionSucceeded {
                    try? FileManager.default.removeItem(at: localAudioFileURL)
                } else if preservedRecordingURL == nil {
                    _ = self.preserveRecordingForRecovery(localAudioFileURL)
                }
            }
        }
    }

    @MainActor
    private func cancelRecordingFromHold() {
        guard state == .recording else { return }
        realtimeTranscriber?.cancel()
        recorderController.cancel()
        realtimeTranscriber = nil
        pendingMeetingRecordingCandidate = nil
        textInsertionController.clearTransientState()
        hotkeyMonitor.cancelCurrentHold()
        state = .idle
        activeCaptureMode = nil
        recordingStartedAt = nil
        lastRecordingDuration = nil
        debugLog("Recording cancelled from hold")
    }

    private func stopLocalRecordingIfNeeded() async -> URL? {
        if recorderController.isRecording {
            do {
                let url = try await recorderController.stopAndAwaitResult()
                await MainActor.run {
                    self.debugLog("Local recording finalized at \(url.lastPathComponent)")
                }
                return url
            } catch {
                await MainActor.run {
                    self.debugLog("Local recorder stop failed: \(error.localizedDescription)")
                }
                return nil
            }
        }

        return recorderController.currentFileURL
    }

    @MainActor
    private func transcriberCancelAndClear() {
        realtimeTranscriber?.cancel()
        realtimeTranscriber = nil
    }

    @MainActor
    private func requestRecordingStart(mode: CaptureMode, meetingCandidate: MeetingSessionCandidate? = nil) {
        guard state == .idle else {
            debugLog("Ignoring recording start for mode=\(mode.displayName) because state=\(state)")
            return
        }
        guard pendingCaptureMode == nil else {
            debugLog("Ignoring duplicate recording start for mode=\(mode.displayName) while another start is pending")
            return
        }
        pendingCaptureMode = mode
        pendingMeetingRecordingCandidate = meetingCandidate
        debugLog("Requesting recording start; microphoneAuth=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording(mode: mode)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    (NSApp.delegate as? SpeakFlowApp)?.handleMicrophonePermissionResult(granted)
                }
            }
        case .denied, .restricted:
            pendingCaptureMode = nil
            pendingMeetingRecordingCandidate = nil
            presentError(message: "Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone.")
        @unknown default:
            pendingCaptureMode = nil
            pendingMeetingRecordingCandidate = nil
            presentError(message: "Microphone permission is unavailable on this system.")
        }
    }

    @MainActor
    private func handleMicrophonePermissionResult(_ granted: Bool) {
        if granted {
            startRecording(mode: pendingCaptureMode ?? .dictation)
        } else {
            pendingCaptureMode = nil
            pendingMeetingRecordingCandidate = nil
            presentError(message: "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone.")
        }
        pendingCaptureMode = nil
    }

    @MainActor
    private func startRecording(mode: CaptureMode) {
        guard state == .idle else {
            debugLog("Ignoring startRecording for mode=\(mode.displayName) because state=\(state)")
            pendingCaptureMode = nil
            return
        }
        do {
            config = try configStore.load()
            pendingCaptureMode = nil
            activeCaptureMode = mode
            if mode == .dictation {
                textInsertionController.captureTargetApplication()
                textInsertionController.prepareForRecording(preferAccessibilityInsertion: config.preferAccessibilityInsertion)
            } else {
                textInsertionController.clearTransientState()
            }
            try recorderController.start()
            let transcriber = ElevenLabsRealtimeTranscriber(config: config)
            transcriber.onDebugLog = { [weak self] message in
                Task { @MainActor in
                    self?.debugLog(message)
                }
            }
            transcriber.onAudioLevelsChanged = { [weak self] levels in
                Task { @MainActor in
                    guard let self, self.state == .recording else { return }
                    self.widgetCoordinator.updateAudioLevels(levels)
                }
            }
            transcriber.onTranscriptChanged = { [weak self] snapshot in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.state == .recording, self.activeCaptureMode == .dictation else { return }
                    self.debugLog("Live dictation transcript update len=\((snapshot as NSString).length)")
                    self.textInsertionController.scheduleLiveInsertion(
                        for: snapshot,
                        isRecording: true,
                        preferAccessibilityInsertion: self.config.preferAccessibilityInsertion,
                        statusHandler: { status in
                            if self.lastPasteStatus != status {
                                self.lastPasteStatus = status
                                self.refreshUI()
                            }
                        }
                    )
                }
            }
            do {
                try transcriber.start(previousText: nil)
                realtimeTranscriber = transcriber
                debugLog("Live audio meter connected")
            } catch {
                realtimeTranscriber = nil
                debugLog("Live audio meter unavailable; continuing with local recording only: \(error.localizedDescription)")
            }
            recordingStartedAt = Date()
            lastRecordingDuration = nil
            state = .recording
            debugLog("\(mode.displayName) capture started successfully")
        } catch {
            recorderController.cancel()
            realtimeTranscriber?.cancel()
            realtimeTranscriber = nil
            pendingMeetingRecordingCandidate = nil
            activeCaptureMode = nil
            recordingStartedAt = nil
            lastRecordingDuration = nil
            state = .idle
            debugLog("Recording failed to start: \(error.localizedDescription)")
            presentError(message: error.localizedDescription)
        }
    }

    private func transcribeRecording(at audioFileURL: URL) async throws -> String {
        config = try configStore.load()
        let providerOrder = transcriptionProviderOrder()
        guard let primary = providerOrder.first else {
            throw SpeakFlowError.transcriptionFailed("No transcription provider is configured.")
        }
        debugLog("Transcription provider order: \(providerOrder.joined(separator: " -> "))")

        do {
            let transcript = try await transcribeRecording(at: audioFileURL, using: primary)
            await MainActor.run {
                self.debugLog("Primary transcription succeeded via \(primary)")
            }
            return transcript
        } catch {
            await MainActor.run {
                self.debugLog("Primary transcription failed via \(primary): \(error.localizedDescription)")
            }

            guard let backup = providerOrder.dropFirst().first else {
                throw error
            }

            do {
                let transcript = try await transcribeRecording(at: audioFileURL, using: backup)
                await MainActor.run {
                    self.debugLog("Backup transcription succeeded via \(backup)")
                }
                return transcript
            } catch {
                await MainActor.run {
                    self.debugLog("Backup transcription failed via \(backup): \(error.localizedDescription)")
                }
                throw error
            }
        }
    }

    private func transcribeRecording(at audioFileURL: URL, using provider: String) async throws -> String {
        let timeout = transcriptionTimeout(for: audioFileURL)
        debugLog("Using \(Int(timeout))s timeout for \(provider) transcription")
        return try await withTimeout(seconds: timeout, operationName: "\(provider) transcription") { [self] in
            switch provider {
            case "elevenlabs":
                let data = try Data(contentsOf: audioFileURL)
                let client = ElevenLabsBatchTranscriberClient(config: self.config)
                return try await client.transcribe(
                    audioData: data,
                    mimeType: self.audioMimeType(for: audioFileURL),
                    fileExtension: audioFileURL.pathExtension.isEmpty ? "m4a" : audioFileURL.pathExtension
                )
            case "openai":
                let client = OpenAICompatibleClient(config: self.config)
                return try await client.transcribe(
                    audioFileURL: audioFileURL,
                    modelOverride: openAITranscriptionFallbackModel
                )
            default:
                throw SpeakFlowError.transcriptionFailed("No transcription provider is configured.")
            }
        }
    }

    private func transcriptionTimeout(for audioFileURL: URL) -> TimeInterval {
        let asset = AVURLAsset(url: audioFileURL)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            return transcriptionTimeoutSeconds
        }
        let dynamicTimeout = duration * 1.5 + 120
        return max(transcriptionTimeoutSeconds, min(30 * 60, dynamicTimeout))
    }

    private func transcriptionProviderOrder() -> [String] {
        let hasOpenAI = config.resolvedOpenAIAPIKey() != nil
        let hasElevenLabs = config.resolvedElevenLabsAPIKey() != nil
        let providerName = config.providerName.lowercased()

        var orderedProviders: [String] = []

        if providerName.contains("openai transcription") {
            orderedProviders.append("openai")
            if providerName.contains("elevenlabs") {
                orderedProviders.append("elevenlabs")
            }
        } else if providerName.contains("elevenlabs") {
            orderedProviders.append("elevenlabs")
            if providerName.contains("openai") {
                orderedProviders.append("openai")
            }
        }

        let availableProviders = [
            hasOpenAI ? "openai" : nil,
            hasElevenLabs ? "elevenlabs" : nil
        ].compactMap { $0 }

        let filteredConfigured = orderedProviders.filter { availableProviders.contains($0) }
        if !filteredConfigured.isEmpty {
            var deduped: [String] = []
            for provider in filteredConfigured where !deduped.contains(provider) {
                deduped.append(provider)
            }
            return deduped
        }

        return availableProviders
    }

    private func activeTranscriptionModelName() -> String {
        switch transcriptionProviderOrder().first {
        case "openai":
            return openAITranscriptionFallbackModel
        case "elevenlabs":
            return config.transcriptionModel
        default:
            return ""
        }
    }

    private func audioMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/x-m4a"
        case "aiff", "aif":
            return "audio/aiff"
        case "mp3":
            return "audio/mpeg"
        default:
            return "application/octet-stream"
        }
    }

    private func applyDictationResult(rawTranscript: String, startedAt: Date, duration: TimeInterval) async {
        do {
            config = try configStore.load()
            let client = OpenAICompatibleClient(config: config)
            let finalText: String
            do {
                let cleaned = try await withTimeout(seconds: cleanupTimeoutSeconds, operationName: "cleanup") {
                    try await client.cleanup(text: rawTranscript)
                }
                finalText = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawTranscript : cleaned
            } catch {
                await MainActor.run {
                    self.debugLog("Cleanup failed; using raw transcript instead: \(error.localizedDescription)")
                }
                finalText = rawTranscript
            }
            await MainActor.run {
                self.realtimeTranscriber = nil
                self.recordingStartedAt = nil
                self.lastRecordingDuration = nil
                self.pendingMeetingRecordingCandidate = nil
                self.activeCaptureMode = nil
                self.textInsertionController.clearTransientState()
                self.lastOutputText = finalText
                if let snapshot = try? self.captureStore.append(
                    kind: .dictationSnippet,
                    startedAt: startedAt,
                    endedAt: Date(),
                    durationSeconds: duration,
                    provider: self.config.providerName,
                    transcriptionModel: self.activeTranscriptionModelName(),
                    cleanupModel: self.config.cleanupEnabled ? self.config.cleanupModel : nil,
                    rawTranscript: rawTranscript,
                    finalText: finalText
                ) {
                    self.captures = snapshot.0
                    self.stats = snapshot.1
                }
                self.enqueuePaste(finalText)
                self.controlCenterWindowController?.update(
                    config: self.config,
                    captures: self.captures,
                    stats: self.stats,
                    isCapturingHotkey: self.isCapturingHotkey,
                    activeCaptureMode: self.activeCaptureMode,
                    summarizingCaptureID: self.summarizingCaptureID
                )
                self.state = .idle
            }
        } catch {
            await MainActor.run {
                self.realtimeTranscriber = nil
                self.recordingStartedAt = nil
                self.lastRecordingDuration = nil
                self.activeCaptureMode = nil
                self.textInsertionController.clearTransientState()
                self.state = .idle
                self.presentError(message: self.userFacingTranscriptionFailureMessage(for: error))
            }
        }
    }

    private func applyRecordingResult(transcript: String, startedAt: Date, duration: TimeInterval) async {
        do {
            config = try configStore.load()
            await MainActor.run {
                let meetingCandidate = self.pendingMeetingRecordingCandidate
                var savedCapture: CaptureRecord?
                self.realtimeTranscriber = nil
                self.recordingStartedAt = nil
                self.lastRecordingDuration = nil
                self.pendingMeetingRecordingCandidate = nil
                self.activeCaptureMode = nil
                self.textInsertionController.clearTransientState()
                if let snapshot = try? self.captureStore.append(
                    kind: .recordingSession,
                    sourceContext: meetingCandidate == nil ? "recording" : "meeting",
                    meetingApp: meetingCandidate?.app.rawValue,
                    meetingTitle: meetingCandidate?.title,
                    startedAt: startedAt,
                    endedAt: Date(),
                    durationSeconds: duration,
                    provider: self.config.providerName,
                    transcriptionModel: self.activeTranscriptionModelName(),
                    cleanupModel: self.config.cleanupEnabled ? self.config.cleanupModel : nil,
                    rawTranscript: transcript,
                    finalText: transcript
                ) {
                    self.captures = snapshot.0
                    self.stats = snapshot.1
                    savedCapture = snapshot.0.first
                }
                self.controlCenterWindowController?.update(
                    config: self.config,
                    captures: self.captures,
                    stats: self.stats,
                    isCapturingHotkey: self.isCapturingHotkey,
                    activeCaptureMode: self.activeCaptureMode,
                    summarizingCaptureID: self.summarizingCaptureID
                )
                if let savedCapture {
                    self.captureNotificationService.notifyRecordingReady(capture: savedCapture)
                }
                self.state = .idle
            }
        } catch {
            await MainActor.run {
                self.realtimeTranscriber = nil
                self.recordingStartedAt = nil
                self.lastRecordingDuration = nil
                self.pendingMeetingRecordingCandidate = nil
                self.activeCaptureMode = nil
                self.textInsertionController.clearTransientState()
                self.state = .idle
                self.presentError(message: self.userFacingTranscriptionFailureMessage(for: error))
            }
        }
    }

    private func shouldSilentlyIgnore(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let silentMarkers = [
            "no transcript arrived",
            "returned an empty transcript",
            "empty transcript",
            "transcript was empty",
            "session could not start",
            "timed out"
        ]
        return silentMarkers.contains { message.contains($0) }
    }

    private func userFacingTranscriptionFailureMessage(for error: Error, preservedRecordingURL: URL? = nil) -> String {
        if shouldSilentlyIgnore(error: error) {
            return appendPreservedRecordingPathIfNeeded(error.localizedDescription, preservedRecordingURL: preservedRecordingURL)
        }

        let message = error.localizedDescription.lowercased()
        let transportMarkers = [
            "elevenlabs send failed",
            "bad response from the server",
            "unexpected response",
            "receive failed",
            "couldn’t be read because it isn’t in the correct format"
        ]

        if transportMarkers.contains(where: { message.contains($0) }) {
            return appendPreservedRecordingPathIfNeeded(
                "Speech recognition temporarily failed. Please try again.",
                preservedRecordingURL: preservedRecordingURL
            )
        }

        return appendPreservedRecordingPathIfNeeded(error.localizedDescription, preservedRecordingURL: preservedRecordingURL)
    }

    private func appendPreservedRecordingPathIfNeeded(_ message: String, preservedRecordingURL: URL?) -> String {
        guard let preservedRecordingURL else { return message }
        return message + "\n\nRecording was saved for retry at:\n\(preservedRecordingURL.path)"
    }

    private func preserveRecordingForRecovery(_ sourceURL: URL) -> URL? {
        let fm = FileManager.default
        let directory = configStore.supportDirectoryURL.appendingPathComponent("failed-recordings", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
            let destination = directory
                .appendingPathComponent("failed-\(timestamp)-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: sourceURL, to: destination)
            debugLog("Preserved failed recording at \(destination.path)")
            return destination
        } catch {
            debugLog("Failed to preserve recording for recovery: \(error.localizedDescription)")
            return nil
        }
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
        guard !isPresentingErrorAlert else {
            debugLog("Skipping duplicate error alert while another alert is visible")
            return
        }

        lastPasteStatus = sanitizedMessage
        refreshUI()

        let makeAlert = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = appDisplayName
            alert.informativeText = message
            return alert
        }

        if let hostWindow = (NSApp.keyWindow ?? NSApp.mainWindow ?? controlCenterWindowController?.window),
           hostWindow.isVisible {
            isPresentingErrorAlert = true
            debugLog("Presenting error as sheet for window=\(hostWindow.title)")
            let alert = makeAlert()
            NSApp.activate(ignoringOtherApps: true)
            alert.beginSheetModal(for: hostWindow) { [weak self] _ in
                Task { @MainActor in
                    self?.isPresentingErrorAlert = false
                    self?.debugLog("Dismissed sheet error alert")
                }
            }
            return
        }

        debugLog("No visible host window for sheet error alert; rendering idle UI without modal block")
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operationName: String,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SpeakFlowError.transcriptionFailed("\(operationName.capitalized) timed out.")
            }

            guard let result = try await group.next() else {
                throw SpeakFlowError.transcriptionFailed("\(operationName.capitalized) timed out.")
            }
            group.cancelAll()
            return result
        }
    }
}
