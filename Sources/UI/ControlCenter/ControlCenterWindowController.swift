import AppKit
import SwiftUI

@MainActor
final class ControlCenterWindowController: NSWindowController {
    enum WorkspacePage: String, CaseIterable, Identifiable {
        case dictation
        case recordings
        case settings

        var id: String { rawValue }
    }

    var onBeginHotkeyCapture: (() -> Void)?
    var onOpenConfigFile: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onUpdateRealtimeModel: ((String) -> Void)?
    var onUpdateBatchModel: ((String) -> Void)?
    var onUpdateCleanupModel: ((String) -> Void)?
    var onSummarizeCapture: ((UUID) -> Void)?

    private let store = ControlCenterWorkspaceStore()

    init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ControlCenterChrome.idealWindowWidth,
                height: ControlCenterChrome.idealWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeakFlow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(
            width: ControlCenterChrome.minimumComfortableWindowWidth,
            height: ControlCenterChrome.minimumComfortableWindowHeight
        )
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        config: AppConfig,
        captures: [CaptureRecord],
        stats: UsageStats,
        isCapturingHotkey: Bool,
        activeCaptureMode: CaptureMode?,
        summarizingCaptureID: UUID?
    ) {
        store.config = config
        store.stats = stats
        store.activeCaptureMode = activeCaptureMode
        store.isCapturingHotkey = isCapturingHotkey
        store.summarizingCaptureID = summarizingCaptureID
        store.dictationCaptures = captures.filter { $0.kind == .dictationSnippet }
        store.recordingCaptures = captures.filter { $0.kind == .recordingSession }
    }

    func ensureWindowIsVisible() {
        guard let window else { return }
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.visibleFrame.intersects(window.frame) }) ?? NSScreen.main ?? screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        var frame = window.frame
        let desiredWidth = min(ControlCenterChrome.idealWindowWidth, visibleFrame.width - 80)
        let desiredHeight = min(ControlCenterChrome.idealWindowHeight, visibleFrame.height - 80)
        let shouldResetSize =
            frame.width < ControlCenterChrome.minimumComfortableWindowWidth ||
            frame.height < ControlCenterChrome.minimumComfortableWindowHeight ||
            !visibleFrame.intersects(frame)

        if shouldResetSize {
            frame.size = NSSize(
                width: max(desiredWidth, ControlCenterChrome.minimumComfortableWindowWidth),
                height: max(desiredHeight, ControlCenterChrome.minimumComfortableWindowHeight)
            )
            frame.origin.x = visibleFrame.midX - frame.width / 2
            frame.origin.y = visibleFrame.midY - frame.height / 2
            window.setFrame(frame, display: true)
        }
    }

    func presentAsPrimaryWorkspaceWindow() {
        ensureWindowIsVisible()
        window?.makeKeyAndOrderFront(nil)
    }

    func present(page: WorkspacePage, selectedRecordingCaptureID: UUID? = nil) {
        store.selectedPage = page
        if page != .dictation {
            store.selectedDictationCaptureID = nil
        }
        if page == .recordings {
            store.selectedRecordingCaptureID = selectedRecordingCaptureID
        } else {
            store.selectedRecordingCaptureID = nil
        }
        presentAsPrimaryWorkspaceWindow()
    }

    private func setupUI() {
        guard let window else { return }
        let rootView = ControlCenterWorkspaceView(
            store: store,
            onBeginHotkeyCapture: { [weak self] in self?.onBeginHotkeyCapture?() },
            onOpenConfigFile: { [weak self] in self?.onOpenConfigFile?() },
            onClearHistory: { [weak self] in self?.onClearHistory?() },
            onUpdateRealtimeModel: { [weak self] in self?.onUpdateRealtimeModel?($0) },
            onUpdateBatchModel: { [weak self] in self?.onUpdateBatchModel?($0) },
            onUpdateCleanupModel: { [weak self] in self?.onUpdateCleanupModel?($0) },
            onSummarizeCapture: { [weak self] in self?.onSummarizeCapture?($0) }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hostingView
    }
}

@MainActor
final class ControlCenterWorkspaceStore: ObservableObject {
    @Published var selectedPage: ControlCenterWindowController.WorkspacePage = .dictation
    @Published var selectedDictationCaptureID: UUID?
    @Published var selectedRecordingCaptureID: UUID?
    @Published var config: AppConfig = .default()
    @Published var stats: UsageStats = .empty
    @Published var activeCaptureMode: CaptureMode?
    @Published var isCapturingHotkey = false
    @Published var summarizingCaptureID: UUID?
    @Published var dictationCaptures: [CaptureRecord] = []
    @Published var recordingCaptures: [CaptureRecord] = []
}

private struct ControlCenterWorkspaceView: View {
    @ObservedObject var store: ControlCenterWorkspaceStore

    let onBeginHotkeyCapture: () -> Void
    let onOpenConfigFile: () -> Void
    let onClearHistory: () -> Void
    let onUpdateRealtimeModel: (String) -> Void
    let onUpdateBatchModel: (String) -> Void
    let onUpdateCleanupModel: (String) -> Void
    let onSummarizeCapture: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedPage: $store.selectedPage)
            VStack(spacing: 0) {
                GlobalHeaderView(
                    providerName: store.config.providerName,
                    hotkey: store.config.resolvedHotkeyBinding().displayName,
                    mode: store.activeCaptureMode?.displayName ?? "Ready"
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        switch store.selectedPage {
                        case .dictation:
                            DictationPageView(
                                stats: store.stats,
                                captures: store.dictationCaptures,
                                selectedCaptureID: $store.selectedDictationCaptureID,
                                onClearHistory: onClearHistory
                            )
                        case .recordings:
                            RecordingsPageView(
                                captures: store.recordingCaptures,
                                selectedCaptureID: $store.selectedRecordingCaptureID,
                                summarizingCaptureID: store.summarizingCaptureID,
                                onClearLibrary: onClearHistory,
                                onSummarizeCapture: onSummarizeCapture
                            )
                        case .settings:
                            SettingsPageView(
                                config: store.config,
                                isCapturingHotkey: store.isCapturingHotkey,
                                onBeginHotkeyCapture: onBeginHotkeyCapture,
                                onOpenConfigFile: onOpenConfigFile,
                                onUpdateRealtimeModel: onUpdateRealtimeModel,
                                onUpdateBatchModel: onUpdateBatchModel,
                                onUpdateCleanupModel: onUpdateCleanupModel
                            )
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 40)
                    .frame(maxWidth: 960, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(ControlCenterPalette.bgApp)
            }
            .background(ControlCenterPalette.bgApp)
        }
        .frame(minWidth: ControlCenterChrome.minimumComfortableWindowWidth, minHeight: ControlCenterChrome.minimumComfortableWindowHeight)
        .background(ControlCenterPalette.bgApp)
        .preferredColorScheme(.dark)
    }
}

private enum ControlCenterPalette {
    static let bgApp = Color(red: 9/255, green: 9/255, blue: 11/255)
    static let bgSidebar = Color(red: 17/255, green: 17/255, blue: 19/255)
    static let bgSurface = Color(red: 24/255, green: 24/255, blue: 27/255)
    static let borderLight = Color(red: 39/255, green: 39/255, blue: 42/255)
    static let borderStrong = Color(red: 63/255, green: 63/255, blue: 70/255)
    static let textPrimary = Color(red: 244/255, green: 244/255, blue: 245/255)
    static let textSecondary = Color(red: 161/255, green: 161/255, blue: 170/255)
    static let textMuted = Color(red: 113/255, green: 113/255, blue: 122/255)
    static let accentTeal = Color(red: 20/255, green: 184/255, blue: 166/255)
    static let accentTealBg = Color(red: 20/255, green: 184/255, blue: 166/255).opacity(0.15)
}

private struct SidebarView: View {
    @Binding var selectedPage: ControlCenterWindowController.WorkspacePage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ControlCenterPalette.bgSurface)
                        .frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ControlCenterPalette.borderStrong, lineWidth: 1))

                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ControlCenterPalette.textSecondary)
                }

                Text("SpeakFlow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ControlCenterPalette.textPrimary)
            }
            .padding(.bottom, 32)
            .padding(.leading, 4)

            Text("WORKSPACES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ControlCenterPalette.textMuted)
                .tracking(0.5)
                .padding(.leading, 8)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                SidebarItem(title: "Dictation", icon: "text.bubble", isSelected: selectedPage == .dictation) {
                    selectedPage = .dictation
                }
                SidebarItem(title: "Recordings", icon: "waveform.path.ecg", isSelected: selectedPage == .recordings) {
                    selectedPage = .recordings
                }

                Spacer().frame(height: 16)

                SidebarItem(title: "Settings", icon: "slider.horizontal.3", isSelected: selectedPage == .settings) {
                    selectedPage = .settings
                }
            }

            Spacer()

            Text("Use Dictation for fast paste-in-place work, Recordings for saved sessions, and Settings for input and model tuning.")
                .font(.system(size: 12))
                .foregroundColor(ControlCenterPalette.textMuted)
                .lineSpacing(4)
                .padding(.horizontal, 8)
        }
        .padding(24)
        .frame(minWidth: 260, idealWidth: 260, maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)
        .background(ControlCenterPalette.bgSidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(ControlCenterPalette.borderLight).frame(width: 1)
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .opacity(isSelected ? 1 : 0.7)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .foregroundColor(isSelected ? ControlCenterPalette.textPrimary : ControlCenterPalette.textSecondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct GlobalHeaderView: View {
    let providerName: String
    let hotkey: String
    let mode: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SpeakFlow")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(ControlCenterPalette.textPrimary)
                Text("Ready to dictate into the current app.")
                    .font(.system(size: 14))
                    .foregroundColor(ControlCenterPalette.textSecondary)
            }

            Spacer()

            HStack(spacing: 12) {
                MetaTag(label: "MODE", value: mode)
                MetaTag(label: "HOTKEY", value: hotkey)
                MetaTag(label: "PROVIDER", value: providerName)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(ControlCenterPalette.bgApp.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ControlCenterPalette.borderLight).frame(height: 1)
        }
    }
}

private struct MetaTag: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(ControlCenterPalette.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(ControlCenterPalette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ControlCenterPalette.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ControlCenterPalette.borderLight, lineWidth: 1))
        .cornerRadius(8)
    }
}

private struct DictationPageView: View {
    let stats: UsageStats
    let captures: [CaptureRecord]
    @Binding var selectedCaptureID: UUID?
    let onClearHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dictation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ControlCenterPalette.textPrimary)
                Text("Hold the global key to speak directly into the focused app. Recent snippets stay reusable here.")
                    .font(.system(size: 14))
                    .foregroundColor(ControlCenterPalette.textSecondary)
            }

            HStack(spacing: 0) {
                MetricItem(label: "Dictations", value: "\(stats.totalDictations)")
                dividerVertical
                MetricItem(label: "Recordings", value: "\(stats.totalRecordings)")
                dividerVertical
                MetricItem(label: "Recorded", value: formatDuration(stats.totalRecordedSeconds))
                dividerVertical
                MetricItem(label: "Last Capture", value: relativeString(stats.lastCaptureAt))
            }
            .background(ControlCenterPalette.bgSurface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ControlCenterPalette.borderLight, lineWidth: 1))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictation Snippets")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ControlCenterPalette.textPrimary)
                    Text("Fast hold-to-talk captures, polished and ready to reuse.")
                        .font(.system(size: 13))
                        .foregroundColor(ControlCenterPalette.textSecondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ControlCenterPalette.bgSurface)
                .border(bottom: true)

                if captures.isEmpty {
                    Text("Your recent dictation snippets will appear here. Hold the global key and speak to create the first one.")
                        .font(.system(size: 13))
                        .foregroundColor(ControlCenterPalette.textMuted)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(captures) { capture in
                        Button {
                            selectedCaptureID = capture.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(capture.finalText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ControlCenterPalette.textPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(timestampString(capture.createdAt)) • \(capture.provider)")
                                    .font(.system(size: 12))
                                    .foregroundColor(ControlCenterPalette.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedCaptureID == capture.id ? Color.white.opacity(0.04) : Color.clear)
                            .border(bottom: capture.id != captures.last?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    PrimaryButton(title: "Copy Selected") {
                        guard let selectedCaptureID,
                              let capture = captures.first(where: { $0.id == selectedCaptureID }) else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(capture.finalText, forType: .string)
                    }
                    .disabled(selectedCaptureID == nil)

                    SecondaryButton(title: "Clear Snippets", action: onClearHistory)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ControlCenterPalette.bgSurface)
            }
            .background(ControlCenterPalette.bgApp)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ControlCenterPalette.borderLight, lineWidth: 1))
            .cornerRadius(8)
        }
    }

    private var dividerVertical: some View {
        Rectangle().fill(ControlCenterPalette.borderLight).frame(width: 1)
    }
}

private struct MetricItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(ControlCenterPalette.textMuted)
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(ControlCenterPalette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecordingsPageView: View {
    let captures: [CaptureRecord]
    @Binding var selectedCaptureID: UUID?
    let summarizingCaptureID: UUID?
    let onClearLibrary: () -> Void
    let onSummarizeCapture: (UUID) -> Void

    var body: some View {
        Group {
            if let selectedCapture = captures.first(where: { $0.id == selectedCaptureID }) {
                RecordingDetailView(
                    capture: selectedCapture,
                    isSummarizing: summarizingCaptureID == selectedCapture.id,
                    onBack: { selectedCaptureID = nil },
                    onSummarize: { onSummarizeCapture(selectedCapture.id) }
                )
            } else {
                RecordingsListView(
                    captures: captures,
                    onClearLibrary: onClearLibrary,
                    onOpenCapture: { selectedCaptureID = $0.id }
                )
            }
        }
    }
}

private struct RecordingsListView: View {
    let captures: [CaptureRecord]
    let onClearLibrary: () -> Void
    let onOpenCapture: (CaptureRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording Library")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ControlCenterPalette.textPrimary)
                    Text("Sticky-recording sessions saved here for deep review and summarization.")
                        .font(.system(size: 14))
                        .foregroundColor(ControlCenterPalette.textSecondary)
                }
                Spacer()
                SecondaryButton(title: "Clear Library", action: onClearLibrary)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("DATE & TIME").frame(width: 200, alignment: .leading)
                    Text("DURATION").frame(width: 100, alignment: .leading)
                    Text("PREVIEW").frame(maxWidth: .infinity, alignment: .leading)
                    Text("STATUS").frame(width: 120, alignment: .leading)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ControlCenterPalette.textMuted)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(ControlCenterPalette.bgSurface)
                .border(bottom: true)

                if captures.isEmpty {
                    Text("Click the widget once to start a recording session. Finished sessions will appear here with transcript and summary tools.")
                        .font(.system(size: 13))
                        .foregroundColor(ControlCenterPalette.textMuted)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(captures) { capture in
                        Button {
                            onOpenCapture(capture)
                        } label: {
                            HStack {
                                Text(recordingDateString(capture.endedAt))
                                    .frame(width: 200, alignment: .leading)
                                    .foregroundColor(ControlCenterPalette.textPrimary)
                                Text(formatDuration(capture.durationSeconds))
                                    .frame(width: 100, alignment: .leading)
                                    .foregroundColor(ControlCenterPalette.textMuted)
                                Text(capture.finalText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundColor(ControlCenterPalette.textSecondary)
                                    .lineLimit(1)
                                StatusBadge(text: capture.summaryStatusText == "Ready" ? "Summary Ready" : "Transcript Ready")
                                    .frame(width: 120, alignment: .leading)
                            }
                            .font(.system(size: 14))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .border(bottom: capture.id != captures.last?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(ControlCenterPalette.bgApp)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ControlCenterPalette.borderLight, lineWidth: 1))
            .cornerRadius(8)
        }
    }
}

private struct RecordingDetailView: View {
    let capture: CaptureRecord
    let isSummarizing: Bool
    let onBack: () -> Void
    let onSummarize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                        Text("Back to Library")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ControlCenterPalette.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                SecondaryButton(title: "Delete") { }
            }
            .padding(.bottom, 24)
            .border(bottom: true)

            VStack(alignment: .leading, spacing: 12) {
                metaRow("RECORDED", "\(detailDateString(capture.endedAt)) (\(formatDuration(capture.durationSeconds)))")
                metaRow("PROVIDER", capture.provider)
            }

            documentPane(title: "Full Transcript", button: AnyView(PrimaryButton(title: "Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(capture.finalText, forType: .string)
            })) {
                Text(capture.finalText)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundColor(ControlCenterPalette.textPrimary)
                    .frame(maxWidth: 800, alignment: .leading)
            }

            documentPane(
                title: "Summary",
                button: AnyView(
                    HStack(spacing: 10) {
                        SecondaryButton(title: isSummarizing ? "Summarizing…" : "Generate Summary") {
                            guard !isSummarizing else { return }
                            onSummarize()
                        }
                        let summaryText = normalizedSummaryText(capture)
                        SecondaryButton(title: "Copy Summary") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(summaryText, forType: .string)
                        }
                        .disabled(summaryText.isEmpty)
                    }
                )
            ) {
                Text(summaryBodyText(capture))
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundColor(capture.summary?.isEmpty == false ? ControlCenterPalette.textPrimary : ControlCenterPalette.textMuted)
                    .frame(maxWidth: 800, alignment: .leading)
            }
        }
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .frame(width: 90, alignment: .leading)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ControlCenterPalette.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ControlCenterPalette.textPrimary)
        }
    }

    private func summaryBodyText(_ capture: CaptureRecord) -> String {
        let trimmed = normalizedSummaryText(capture)
        if trimmed.isEmpty {
            return "No summary has been generated for this session yet. Click the button above to generate one using GPT-4o."
        }
        return trimmed
    }

    private func normalizedSummaryText(_ capture: CaptureRecord) -> String {
        capture.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func documentPane(title: String, button: AnyView, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ControlCenterPalette.textPrimary)
                Spacer()
                button
            }
            .padding(.bottom, 16)
            .border(bottom: true)

            content()
        }
        .padding(32)
        .background(ControlCenterPalette.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ControlCenterPalette.borderLight, lineWidth: 1))
        .cornerRadius(8)
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(ControlCenterPalette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ControlCenterPalette.borderStrong, lineWidth: 1))
            .cornerRadius(4)
    }
}

private struct SettingsPageView: View {
    let config: AppConfig
    let isCapturingHotkey: Bool
    let onBeginHotkeyCapture: () -> Void
    let onOpenConfigFile: () -> Void
    let onUpdateRealtimeModel: (String) -> Void
    let onUpdateBatchModel: (String) -> Void
    let onUpdateCleanupModel: (String) -> Void

    @State private var realtimeModel = ""
    @State private var batchModel = ""
    @State private var cleanupModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ControlCenterPalette.textPrimary)
                Text("Configure capture, transcription, cleanup, and clipboard behavior.")
                    .font(.system(size: 14))
                    .foregroundColor(ControlCenterPalette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current shortcut")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ControlCenterPalette.textSecondary)
                Text(config.resolvedHotkeyBinding().displayName)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(ControlCenterPalette.textPrimary)
                Text(isCapturingHotkey ? "Press Fn, Right Command, Right Control, or Ctrl+Option+Space." : "Click Change Hotkey, then press the shortcut you want to keep.")
                    .font(.system(size: 13))
                    .foregroundColor(ControlCenterPalette.textMuted)
                    .padding(.bottom, 8)

                HStack(spacing: 12) {
                    PrimaryButton(title: isCapturingHotkey ? "Listening…" : "Change Hotkey", action: onBeginHotkeyCapture)
                    SecondaryButton(title: "Open Config File", action: onOpenConfigFile)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(title: "Capture")
                SettingsRow(key: "Language Hint", value: config.transcriptionLanguageHint.isEmpty ? "Auto detect" : config.transcriptionLanguageHint.uppercased())
                SettingsRow(key: "Cleanup", value: config.cleanupEnabled ? config.cleanupModel : "Disabled")
                SettingsRow(key: "Clipboard", value: config.restoreClipboard ? "Restore after paste" : "Leave latest result", isLast: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(title: "Transcription Models")
                SettingsMenuRow(
                    key: "Realtime STT",
                    selection: $realtimeModel,
                    options: elevenLabsRealtimeModelPresets
                )
                .onChange(of: realtimeModel) { _, value in
                    guard !value.isEmpty else { return }
                    onUpdateRealtimeModel(value)
                }

                SettingsMenuRow(
                    key: "Batch STT",
                    selection: $batchModel,
                    options: elevenLabsBatchModelPresets
                )
                .onChange(of: batchModel) { _, value in
                    guard !value.isEmpty else { return }
                    onUpdateBatchModel(value)
                }

                SettingsMenuRow(
                    key: "Cleanup",
                    selection: $cleanupModel,
                    options: openAICleanupModelPresets,
                    isLast: true
                )
                .onChange(of: cleanupModel) { _, value in
                    guard !value.isEmpty else { return }
                    onUpdateCleanupModel(value)
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .onAppear {
            realtimeModel = config.elevenLabsRealtimeModel
            batchModel = config.transcriptionModel
            cleanupModel = config.cleanupModel
        }
        .onChange(of: config.elevenLabsRealtimeModel) { _, value in
            realtimeModel = value
        }
        .onChange(of: config.transcriptionModel) { _, value in
            batchModel = value
        }
        .onChange(of: config.cleanupModel) { _, value in
            cleanupModel = value
        }
    }
}

private struct SettingsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ControlCenterPalette.textPrimary)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .border(top: true)
    }
}

private struct SettingsRow: View {
    let key: String
    let value: String
    var isLast = false

    var body: some View {
        HStack {
            Text(key)
                .frame(width: 200, alignment: .leading)
                .foregroundColor(ControlCenterPalette.textSecondary)
            Text(value)
                .foregroundColor(ControlCenterPalette.textPrimary)
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.vertical, 16)
        .border(bottom: !isLast)
    }
}

private struct SettingsMenuRow: View {
    let key: String
    @Binding var selection: String
    let options: [String]
    var isLast = false

    var body: some View {
        HStack {
            Text(key)
                .frame(width: 200, alignment: .leading)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ControlCenterPalette.textSecondary)

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 240)

            Spacer()
        }
        .padding(.vertical, 12)
        .border(bottom: !isLast)
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ControlCenterPalette.accentTeal)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ControlCenterPalette.accentTealBg)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ControlCenterPalette.accentTeal.opacity(0.3), lineWidth: 1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ControlCenterPalette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ControlCenterPalette.bgSurface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ControlCenterPalette.borderStrong, lineWidth: 1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func border(bottom: Bool = false, top: Bool = false) -> some View {
        overlay(
            ZStack {
                if bottom {
                    Rectangle()
                        .fill(ControlCenterPalette.borderLight)
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                if top {
                    Rectangle()
                        .fill(ControlCenterPalette.borderLight)
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        )
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded(.down)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

private func relativeString(_ date: Date?) -> String {
    guard let date else { return "Never" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func timestampString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM/yyyy, HH:mm"
    return formatter.string(from: date)
}

private func recordingDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM yyyy, HH:mm"
    return formatter.string(from: date)
}

private func detailDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMMM yyyy 'at' HH:mm"
    return formatter.string(from: date)
}
