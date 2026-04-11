import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Foundation
let appDisplayName = "SpeakFlow"
let debugLogPath = "/tmp/speakflow-debug.log"
let minimumIntentionalRecordingDuration: TimeInterval = 0.35
let widgetOuterSize = NSSize(width: 176, height: 38)
let widgetCapsuleSize = NSSize(width: 154, height: 26)

enum DictationState {
    case idle
    case recording
    case transcribing
}

func makePulseImage(size: NSSize, color: NSColor, backgroundColor: NSColor? = nil, template: Bool = false) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    let bounds = NSRect(origin: .zero, size: size)

    if let backgroundColor {
        let outer = NSBezierPath(roundedRect: bounds, xRadius: size.height * 0.28, yRadius: size.height * 0.28)
        backgroundColor.setFill()
        outer.fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        outer.lineWidth = 1
        outer.stroke()
    }

    let centerY = size.height * 0.5
    let lineHeight = max(1.5, size.height * 0.04)
    let lineWidth = size.width * 0.42
    let lineRect = NSRect(x: size.width * 0.29, y: centerY - lineHeight / 2, width: lineWidth, height: lineHeight)
    let line = NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
    color.setFill()
    line.fill()

    let pulseHeights: [CGFloat] = [0.14, 0.26, 0.42, 0.64, 0.42, 0.26, 0.14].map { size.height * $0 }
    let pulseWidth = max(1.8, size.width * 0.028)
    let spacing = max(1.6, size.width * 0.018)
    let totalWidth = CGFloat(pulseHeights.count) * pulseWidth + CGFloat(pulseHeights.count - 1) * spacing
    let startX = size.width * 0.5 - totalWidth / 2
    for (index, height) in pulseHeights.enumerated() {
        let x = startX + CGFloat(index) * (pulseWidth + spacing)
        let rect = NSRect(x: x, y: centerY - height / 2, width: pulseWidth, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: pulseWidth / 2, yRadius: pulseWidth / 2)
        color.setFill()
        path.fill()
    }

    image.unlockFocus()
    image.isTemplate = template
    return image
}

func loadBundledAppIconImage() -> NSImage? {
    if let resourceURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let image = NSImage(contentsOf: resourceURL) {
        return image
    }
    return NSImage(named: "AppIcon")
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
