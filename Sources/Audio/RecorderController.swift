import AVFoundation
import Foundation
final class RecorderController: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?
    var onStop: ((Result<URL, Error>) -> Void)?

    func start() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speakflow-\(ProcessInfo.processInfo.globallyUniqueString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw SpeakFlowError.unableToCaptureAudio
        }

        self.recorder = recorder
        currentFileURL = fileURL
    }

    func stop() {
        recorder?.stop()
    }

    func stopAndAwaitResult() async throws -> URL {
        guard recorder != nil else {
            throw SpeakFlowError.noRecordedFile
        }

        return try await withCheckedThrowingContinuation { continuation in
            let previous = onStop
            onStop = { [weak self] result in
                self?.onStop = previous
                previous?(result)
                continuation.resume(with: result)
            }
            self.stop()
        }
    }

    func cancel() {
        recorder?.stop()
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        currentFileURL = nil
    }

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let fileURL = currentFileURL
        self.recorder = nil
        currentFileURL = nil

        guard flag, let fileURL else {
            onStop?(.failure(SpeakFlowError.noRecordedFile))
            return
        }
        onStop?(.success(fileURL))
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let finalError = error ?? SpeakFlowError.unableToCaptureAudio
        self.recorder = nil
        let fileURL = currentFileURL
        currentFileURL = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        onStop?(.failure(finalError))
    }
}
