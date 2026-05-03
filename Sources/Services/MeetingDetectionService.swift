import AppKit
import CoreGraphics
import Foundation

@MainActor
final class MeetingDetectionService {
    private struct WindowObservation {
        let ownerName: String
        let title: String
        let matched: Bool
    }

    private struct DetectionSnapshot {
        let frontmostAppName: String
        let frontmostBundleID: String
        let frontmostMeetingApp: MeetingAppKind?
        let observedWindows: [WindowObservation]
        let candidate: MeetingSessionCandidate?

        var logLine: String {
            let appPart = "frontmost=\(frontmostAppName) bundle=\(frontmostBundleID) meetingApp=\(frontmostMeetingApp?.rawValue ?? "none")"
            let windowsPart: String
            if observedWindows.isEmpty {
                windowsPart = "windows=[]"
            } else {
                let rendered = observedWindows.map { observation in
                    let title = observation.title.isEmpty ? "<empty>" : observation.title
                    return "\(observation.matched ? "match" : "seen"){\(observation.ownerName): \(title)}"
                }.joined(separator: ", ")
                windowsPart = "windows=[\(rendered)]"
            }
            let candidatePart = "candidate=\(candidate?.signature ?? "none")"
            return "\(appPart) \(windowsPart) \(candidatePart)"
        }
    }

    var onMeetingDetected: ((MeetingSessionCandidate) -> Void)?
    var onMeetingEnded: (() -> Void)?

    private let debugLog: (String) -> Void
    private var pollTimer: Timer?
    private var pendingDetectionWorkItem: DispatchWorkItem?
    private var currentCandidate: MeetingSessionCandidate?
    private var announcedSignature: String?
    private var dismissedSignature: String?
    private var lastSnapshotLogLine: String?

    init(debugLog: @escaping (String) -> Void) {
        self.debugLog = debugLog
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceChange),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceChange),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        evaluate()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
        pendingDetectionWorkItem?.cancel()
        pendingDetectionWorkItem = nil
        currentCandidate = nil
        announcedSignature = nil
        dismissedSignature = nil
    }

    func dismissCurrentMeetingPrompt() {
        dismissedSignature = currentCandidate?.signature
        pendingDetectionWorkItem?.cancel()
        pendingDetectionWorkItem = nil
        debugLog("Meeting prompt dismissed for signature=\(dismissedSignature ?? "none")")
    }

    @objc
    private func handleWorkspaceChange() {
        evaluate()
    }

    private func evaluate() {
        let snapshot = buildDetectionSnapshot()
        if snapshot.logLine != lastSnapshotLogLine {
            debugLog("Meeting detection scan: \(snapshot.logLine)")
            lastSnapshotLogLine = snapshot.logLine
        }

        let nextCandidate = snapshot.candidate

        guard let nextCandidate else {
            if currentCandidate != nil || announcedSignature != nil {
                debugLog("Meeting detection cleared")
                currentCandidate = nil
                announcedSignature = nil
                dismissedSignature = nil
                pendingDetectionWorkItem?.cancel()
                pendingDetectionWorkItem = nil
                onMeetingEnded?()
            }
            return
        }

        if currentCandidate?.signature != nextCandidate.signature {
            debugLog("Meeting candidate changed to \(nextCandidate.app.displayName) title=\(nextCandidate.title)")
        }

        currentCandidate = nextCandidate

        guard dismissedSignature != nextCandidate.signature else { return }
        guard announcedSignature != nextCandidate.signature else { return }

        pendingDetectionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.currentCandidate?.signature == nextCandidate.signature else { return }
            self.announcedSignature = nextCandidate.signature
            self.debugLog("Meeting detected via \(nextCandidate.app.displayName) title=\(nextCandidate.title)")
            self.onMeetingDetected?(nextCandidate)
        }
        pendingDetectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
        debugLog("Meeting detection pending for signature=\(nextCandidate.signature)")
    }

    private func buildDetectionSnapshot() -> DetectionSnapshot {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostAppName = frontmostApp?.localizedName ?? "none"
        let frontmostBundleID = frontmostApp?.bundleIdentifier ?? ""
        guard let frontmostApp,
              let frontmostMeetingApp = meetingAppKind(
                ownerName: frontmostApp.localizedName ?? "",
                bundleID: frontmostApp.bundleIdentifier
              ) else {
            return DetectionSnapshot(
                frontmostAppName: frontmostAppName,
                frontmostBundleID: frontmostBundleID,
                frontmostMeetingApp: nil,
                observedWindows: [],
                candidate: nil
            )
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var observedWindows: [WindowObservation] = []

        let candidateWindows = windows.compactMap { info -> MeetingSessionCandidate? in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let app = meetingAppKind(ownerName: ownerName, bundleID: frontmostApp.bundleIdentifier),
                  app == frontmostMeetingApp else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matched = !title.isEmpty && looksLikeMeetingTitle(title)
            observedWindows.append(
                WindowObservation(ownerName: ownerName, title: title, matched: matched)
            )
            guard matched else {
                return nil
            }

            let signature = "\(app.rawValue)|\(normalizedMeetingTitle(title))"
            return MeetingSessionCandidate(signature: signature, app: app, title: title)
        }

        return DetectionSnapshot(
            frontmostAppName: frontmostAppName,
            frontmostBundleID: frontmostBundleID,
            frontmostMeetingApp: frontmostMeetingApp,
            observedWindows: observedWindows,
            candidate: candidateWindows.first
        )
    }

    private func meetingAppKind(ownerName: String, bundleID: String?) -> MeetingAppKind? {
        let owner = ownerName.lowercased()
        let bundleID = bundleID?.lowercased() ?? ""

        if owner.contains("zoom") || bundleID.contains("zoom") {
            return .zoom
        }

        if owner.contains("teams") || bundleID.contains("teams") {
            return .teams
        }

        return nil
    }

    private func looksLikeMeetingTitle(_ title: String) -> Bool {
        let normalized = title.lowercased()
        let keywords = [
            "meeting", "zoom meeting", "teams meeting", "call", "huddle",
            "webinar", "sync", "standup", "stand-up", "in progress", "recording",
            "compact view", "live"
        ]
        return keywords.contains(where: normalized.contains)
    }

    private func normalizedMeetingTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
