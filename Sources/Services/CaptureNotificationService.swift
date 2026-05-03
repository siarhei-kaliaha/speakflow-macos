import Foundation
import UserNotifications

@MainActor
final class CaptureNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private enum Constants {
        static let recordingReadyIdentifier = "speakflow.recording.ready"
        static let captureIDKey = "captureID"
    }

    var onOpenRecordingCapture: ((UUID) -> Void)?

    private let debugLog: (String) -> Void
    private let center = UNUserNotificationCenter.current()

    init(debugLog: @escaping (String) -> Void) {
        self.debugLog = debugLog
    }

    func configure() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [debugLog] granted, error in
            if let error {
                debugLog("Notification authorization failed: \(error.localizedDescription)")
            } else {
                debugLog("Notification authorization granted=\(granted)")
            }
        }
    }

    func notifyRecordingReady(capture: CaptureRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Recording ready"
        content.body = capture.title.isEmpty ? "Your recording is ready in SpeakFlow." : capture.title
        content.sound = .default
        content.userInfo = [Constants.captureIDKey: capture.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "\(Constants.recordingReadyIdentifier).\(capture.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        center.add(request) { [debugLog] error in
            if let error {
                debugLog("Failed to schedule recording notification: \(error.localizedDescription)")
            } else {
                debugLog("Scheduled recording notification for capture=\(capture.id.uuidString)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let captureIDString = response.notification.request.content.userInfo[Constants.captureIDKey] as? String
        let captureID = captureIDString.flatMap(UUID.init(uuidString:))

        Task { @MainActor [weak self] in
            if let captureID {
                self?.debugLog("Opening recording capture from notification capture=\(captureID.uuidString)")
                self?.onOpenRecordingCapture?(captureID)
            }
            completionHandler()
        }
    }
}
