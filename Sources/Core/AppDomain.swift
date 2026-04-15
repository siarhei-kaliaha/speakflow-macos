import Foundation

let appDisplayName = "SpeakFlow"
let debugLogPath = "/tmp/speakflow-debug.log"
let minimumIntentionalRecordingDuration: TimeInterval = 0.35

enum DictationState {
    case idle
    case recording
    case transcribing
}

enum CaptureMode: String, Codable, CaseIterable {
    case dictation
    case recording

    var displayName: String {
        switch self {
        case .dictation:
            return "Dictation"
        case .recording:
            return "Recording"
        }
    }
}

enum CaptureKind: String, Codable, CaseIterable {
    case dictationSnippet
    case recordingSession
}

enum CaptureStatus: String, Codable {
    case completed
    case cancelled
    case failed
}

enum HotkeyBinding: String, CaseIterable, Codable {
    case fn = "fn"
    case ctrlOptionSpace = "ctrl_option_space"
    case rightCommand = "right_command"
    case rightControl = "right_control"

    var displayName: String {
        switch self {
        case .fn:
            return "Fn / Globe"
        case .ctrlOptionSpace:
            return "Ctrl+Option+Space"
        case .rightCommand:
            return "Right Command"
        case .rightControl:
            return "Right Control"
        }
    }
}

let elevenLabsRealtimeModelPresets = [
    "scribe_v2_realtime"
]

let elevenLabsBatchModelPresets = [
    "scribe_v2"
]

let openAICleanupModelPresets = [
    "gpt-5.1",
    "gpt-5.1-chat-latest",
    "gpt-4o-mini"
]

let openAITranscriptionFallbackModel = "gpt-4o-transcribe"

enum SpeakFlowError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL(String)
    case unableToCaptureAudio
    case unableToEncodeConfig
    case transcriptionFailed(String)
    case cleanupFailed(String)
    case noRecordedFile

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key in the SpeakFlow config file or set OPENAI_API_KEY before using dictation."
        case .invalidBaseURL(let value):
            return "The configured base URL is invalid: \(value)"
        case .unableToCaptureAudio:
            return "SpeakFlow could not start microphone recording."
        case .unableToEncodeConfig:
            return "SpeakFlow could not write the default configuration file."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .cleanupFailed(let message):
            return "Cleanup failed: \(message)"
        case .noRecordedFile:
            return "Recording finished, but no audio file was produced."
        }
    }
}
