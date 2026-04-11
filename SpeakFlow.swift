#!/usr/bin/env swift
import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Foundation

private let appDisplayName = "SpeakFlow"
private let widgetOriginXKey = "SpeakFlowWidgetOriginX"
private let widgetOriginYKey = "SpeakFlowWidgetOriginY"
private let debugLogPath = "/tmp/speakflow-debug.log"
private let minimumIntentionalRecordingDuration: TimeInterval = 0.35
private let widgetOuterSize = NSSize(width: 176, height: 38)
private let widgetCapsuleSize = NSSize(width: 154, height: 26)

private func makePulseImage(size: NSSize, color: NSColor, backgroundColor: NSColor? = nil, template: Bool = false) -> NSImage {
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

private func loadBundledAppIconImage() -> NSImage? {
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

private let elevenLabsRealtimeModelPresets = [
    "scribe_v2_realtime"
]

private let elevenLabsBatchModelPresets = [
    "scribe_v2"
]

private let openAICleanupModelPresets = [
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

struct AppConfig: Codable {
    var providerName: String
    var baseURL: String
    var apiKey: String
    var elevenLabsAPIKey: String
    var transcriptionModel: String
    var elevenLabsRealtimeModel: String
    var transcriptionLanguageHint: String
    var transcriptionPrompt: String
    var cleanupEnabled: Bool
    var cleanupModel: String
    var cleanupPrompt: String
    var customVocabulary: [String]
    var restoreClipboard: Bool
    var preferAccessibilityInsertion: Bool
    var hotkeyBinding: String

    enum CodingKeys: String, CodingKey {
        case providerName
        case baseURL
        case apiKey
        case elevenLabsAPIKey
        case transcriptionModel
        case elevenLabsRealtimeModel
        case transcriptionLanguageHint
        case transcriptionPrompt
        case cleanupEnabled
        case cleanupModel
        case cleanupPrompt
        case customVocabulary
        case restoreClipboard
        case preferAccessibilityInsertion
        case hotkeyBinding
    }

    static func `default`() -> AppConfig {
        AppConfig(
            providerName: "ElevenLabs realtime + OpenAI cleanup",
            baseURL: "https://api.openai.com/v1",
            apiKey: "",
            elevenLabsAPIKey: "",
            transcriptionModel: "scribe_v2",
            elevenLabsRealtimeModel: "scribe_v2_realtime",
            transcriptionLanguageHint: "",
            transcriptionPrompt: """
Transcribe the recording faithfully.
Do not translate.
If the speaker talks in English, output English.
If the speaker talks in Russian, output Russian.
Only mix English and Russian when the speaker actually mixes them.
Preserve names, product terms, and intended formatting.
Return plain text only.
""",
            cleanupEnabled: true,
            cleanupModel: "gpt-5.1",
            cleanupPrompt: """
You are cleaning dictated text after speech recognition.
Keep the speaker's meaning and language choice intact.
Never translate the text into another language.
Fix punctuation, casing, and obvious speech-to-text mistakes.
Remove filler words only when they add no meaning.
English must stay English. Russian must stay Russian.
Mixed English and Russian should still read naturally.
Return plain text only with no commentary.
""",
            customVocabulary: [
                "OpenAI",
                "macOS",
                "Dictation",
                "ChatGPT"
            ],
            restoreClipboard: true,
            preferAccessibilityInsertion: true,
            hotkeyBinding: HotkeyBinding.fn.rawValue
        )
    }

    init(
        providerName: String,
        baseURL: String,
        apiKey: String,
        elevenLabsAPIKey: String,
        transcriptionModel: String,
        elevenLabsRealtimeModel: String,
        transcriptionLanguageHint: String,
        transcriptionPrompt: String,
        cleanupEnabled: Bool,
        cleanupModel: String,
        cleanupPrompt: String,
        customVocabulary: [String],
        restoreClipboard: Bool,
        preferAccessibilityInsertion: Bool,
        hotkeyBinding: String
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.elevenLabsAPIKey = elevenLabsAPIKey
        self.transcriptionModel = transcriptionModel
        self.elevenLabsRealtimeModel = elevenLabsRealtimeModel
        self.transcriptionLanguageHint = transcriptionLanguageHint
        self.transcriptionPrompt = transcriptionPrompt
        self.cleanupEnabled = cleanupEnabled
        self.cleanupModel = cleanupModel
        self.cleanupPrompt = cleanupPrompt
        self.customVocabulary = customVocabulary
        self.restoreClipboard = restoreClipboard
        self.preferAccessibilityInsertion = preferAccessibilityInsertion
        self.hotkeyBinding = hotkeyBinding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.default()

        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? defaults.providerName
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        elevenLabsAPIKey = try container.decodeIfPresent(String.self, forKey: .elevenLabsAPIKey) ?? defaults.elevenLabsAPIKey
        transcriptionModel = try container.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? defaults.transcriptionModel
        elevenLabsRealtimeModel = try container.decodeIfPresent(String.self, forKey: .elevenLabsRealtimeModel) ?? defaults.elevenLabsRealtimeModel
        transcriptionLanguageHint = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguageHint) ?? defaults.transcriptionLanguageHint
        transcriptionPrompt = try container.decodeIfPresent(String.self, forKey: .transcriptionPrompt) ?? defaults.transcriptionPrompt
        cleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? defaults.cleanupEnabled
        cleanupModel = try container.decodeIfPresent(String.self, forKey: .cleanupModel) ?? defaults.cleanupModel
        cleanupPrompt = try container.decodeIfPresent(String.self, forKey: .cleanupPrompt) ?? defaults.cleanupPrompt
        customVocabulary = try container.decodeIfPresent([String].self, forKey: .customVocabulary) ?? defaults.customVocabulary
        restoreClipboard = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? defaults.restoreClipboard
        preferAccessibilityInsertion = try container.decodeIfPresent(Bool.self, forKey: .preferAccessibilityInsertion) ?? defaults.preferAccessibilityInsertion
        hotkeyBinding = try container.decodeIfPresent(String.self, forKey: .hotkeyBinding) ?? defaults.hotkeyBinding
    }

    func resolvedHotkeyBinding() -> HotkeyBinding {
        HotkeyBinding(rawValue: hotkeyBinding) ?? .fn
    }

    func resolvedOpenAIAPIKey() -> String? {
        let inline = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        return nil
    }

    func resolvedElevenLabsAPIKey() -> String? {
        let inline = elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        return nil
    }

    func resolvedTranscriptionPrompt() -> String {
        var sections = [transcriptionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !customVocabulary.isEmpty {
            let vocabulary = customVocabulary.joined(separator: ", ")
            sections.append("Prefer these spellings when they match the audio: \(vocabulary)")
        }
        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

final class ConfigStore {
    let supportDirectoryURL: URL
    let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDirectoryURL = appSupport.appendingPathComponent(appDisplayName, isDirectory: true)
        configURL = supportDirectoryURL.appendingPathComponent("config.json")
    }

    @discardableResult
    func ensureConfigExists() throws -> Bool {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else {
            return false
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(AppConfig.default())
        } catch {
            throw SpeakFlowError.unableToEncodeConfig
        }

        var finalData = data
        if finalData.last != 0x0A {
            finalData.append(0x0A)
        }
        try finalData.write(to: configURL, options: .atomic)
        return true
    }

    func load() throws -> AppConfig {
        _ = try ensureConfigExists()
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(config)
        if data.last != 0x0A {
            data.append(0x0A)
        }
        try data.write(to: configURL, options: .atomic)
    }
}

struct HistoryEntry: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let text: String
    let provider: String
    let characters: Int
    let words: Int
}

struct UsageStats: Codable {
    var totalDictations: Int
    var totalCharacters: Int
    var totalWords: Int
    var lastDictationAt: Date?

    static let empty = UsageStats(totalDictations: 0, totalCharacters: 0, totalWords: 0, lastDictationAt: nil)
}

final class HistoryStore {
    private let supportDirectoryURL: URL
    private let historyURL: URL
    private let statsURL: URL

    init(baseDirectory: URL) {
        supportDirectoryURL = baseDirectory
        historyURL = baseDirectory.appendingPathComponent("history.json")
        statsURL = baseDirectory.appendingPathComponent("stats.json")
    }

    func loadHistory() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL),
              let items = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return items
    }

    func loadStats() -> UsageStats {
        guard let data = try? Data(contentsOf: statsURL),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data) else {
            return .empty
        }
        return stats
    }

    func append(text: String, provider: String) throws -> ([HistoryEntry], UsageStats) {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        var history = loadHistory()
        var stats = loadStats()

        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: text,
            provider: provider,
            characters: text.count,
            words: words
        )
        history.insert(entry, at: 0)
        history = Array(history.prefix(100))

        stats.totalDictations += 1
        stats.totalCharacters += text.count
        stats.totalWords += words
        stats.lastDictationAt = entry.createdAt

        try saveHistory(history)
        try saveStats(stats)
        return (history, stats)
    }

    func clearHistory() throws {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        try saveHistory([])
    }

    private func saveHistory(_ history: [HistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(history)
        if data.last != 0x0A {
            data.append(0x0A)
        }
        try data.write(to: historyURL, options: .atomic)
    }

    private func saveStats(_ stats: UsageStats) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(stats)
        if data.last != 0x0A {
            data.append(0x0A)
        }
        try data.write(to: statsURL, options: .atomic)
    }
}

struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return representations
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for itemMap in items {
            let item = NSPasteboardItem()
            for (type, data) in itemMap {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}

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

struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

struct ElevenLabsTranscriptResponse: Decodable {
    let text: String
}

struct MultipartFormData {
    let boundary = "Boundary-\(UUID().uuidString)"
    private(set) var body = Data()

    mutating func addField(name: String, value: String) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendUTF8(value)
        body.appendUTF8("\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendUTF8("\r\n")
    }

    func finalized() -> Data {
        var final = body
        final.appendUTF8("--\(boundary)--\r\n")
        return final
    }
}

extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLEUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLEUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

struct OpenAICompatibleClient {
    let config: AppConfig

    private func endpointURL(_ suffix: String) throws -> URL {
        let trimmed = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + suffix) else {
            throw SpeakFlowError.invalidBaseURL(config.baseURL)
        }
        return url
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        guard let apiKey = config.resolvedOpenAIAPIKey() else {
            throw SpeakFlowError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        return request
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        let url = try endpointURL("/audio/transcriptions")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"

        var multipart = MultipartFormData()
        multipart.addField(name: "model", value: config.transcriptionModel)
        multipart.addField(name: "prompt", value: config.resolvedTranscriptionPrompt())
        multipart.addField(name: "response_format", value: "text")
        let languageHint = config.transcriptionLanguageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !languageHint.isEmpty {
            multipart.addField(name: "language", value: languageHint)
        }
        let data = try Data(contentsOf: audioFileURL)
        multipart.addFile(name: "file", filename: audioFileURL.lastPathComponent, mimeType: "audio/m4a", data: data)

        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.finalized()

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: responseData, failureCase: SpeakFlowError.transcriptionFailed)

        let text = String(decoding: responseData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw SpeakFlowError.transcriptionFailed("The speech-to-text API returned an empty transcript.")
        }
        return text
    }

    func cleanup(text: String) async throws -> String {
        guard config.cleanupEnabled else {
            return text
        }

        guard config.resolvedOpenAIAPIKey() != nil else {
            return text
        }

        let url = try endpointURL("/chat/completions")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatCompletionRequest(
            model: config.cleanupModel,
            messages: [
                .init(role: "system", content: config.cleanupPrompt),
                .init(role: "user", content: text)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: responseData, failureCase: SpeakFlowError.cleanupFailed)

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
        let cleaned = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleaned.isEmpty {
            throw SpeakFlowError.cleanupFailed("The cleanup model returned an empty result.")
        }
        return cleaned
    }

    private func validateHTTPResponse(
        _ response: URLResponse,
        data: Data,
        failureCase: (String) -> SpeakFlowError
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw failureCase("The server did not return an HTTP response.")
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw failureCase("HTTP \(http.statusCode): \(body)")
        }
    }
}

struct ElevenLabsBatchTranscriberClient {
    let config: AppConfig

    func transcribe(audioData: Data, mimeType: String = "audio/wav", fileExtension: String = "wav") async throws -> String {
        guard let apiKey = config.resolvedElevenLabsAPIKey() else {
            throw SpeakFlowError.transcriptionFailed("Add `elevenLabsAPIKey` to the SpeakFlow config or set `ELEVENLABS_API_KEY`.")
        }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text") else {
            throw SpeakFlowError.transcriptionFailed("Could not build the ElevenLabs batch speech-to-text URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 180

        var multipart = MultipartFormData()
        multipart.addField(name: "model_id", value: config.transcriptionModel)
        let language = config.transcriptionLanguageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !language.isEmpty {
            multipart.addField(name: "language_code", value: language)
        }

        let prompt = config.resolvedTranscriptionPrompt().trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            multipart.addField(name: "prompt", value: prompt)
        }

        multipart.addFile(
            name: "file",
            filename: "speakflow-fallback.\(fileExtension)",
            mimeType: mimeType,
            data: audioData
        )

        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.finalized()

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SpeakFlowError.transcriptionFailed("The ElevenLabs batch API did not return an HTTP response.")
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(decoding: responseData, as: UTF8.self)
            throw SpeakFlowError.transcriptionFailed("ElevenLabs batch HTTP \(http.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(ElevenLabsTranscriptResponse.self, from: responseData)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw SpeakFlowError.transcriptionFailed("The ElevenLabs batch API returned an empty transcript.")
        }
        return text
    }
}

final class ElevenLabsRealtimeTranscriber {
    var onTranscriptChanged: ((String) -> Void)?

    private let config: AppConfig
    private let sampleRate = 16_000.0
    private let stateQueue = DispatchQueue(label: "local.speakflow.elevenlabs.state")
    private let sendQueue = DispatchQueue(label: "local.speakflow.elevenlabs.send")
    private let session = URLSession(configuration: .default)

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var previousText: String?

    private var committedTranscript = ""
    private var partialTranscript = ""
    private var capturedPCMData = Data()
    private var pendingError: Error?
    private var lastCommittedAt: Date?
    private var lastPartialAt: Date?
    private var closed = false

    init(config: AppConfig) {
        self.config = config
    }

    func start(previousText: String?) throws {
        guard let apiKey = config.resolvedElevenLabsAPIKey() else {
            throw SpeakFlowError.transcriptionFailed("Add `elevenLabsAPIKey` to the SpeakFlow config or set `ELEVENLABS_API_KEY`.")
        }

        let url = try makeRealtimeURL()
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        self.previousText = previousText?.trimmingCharacters(in: .whitespacesAndNewlines)
        task.resume()
        receiveNextMessage()
        try startAudioEngine()
    }

    func finish() async throws -> String {
        try await Task.sleep(nanoseconds: 180_000_000)
        stopAudioEngine()
        try sendFinalizationFrame()
        return try await awaitFinalTranscript()
    }

    func cancel() {
        stopAudioEngine()
        closeSocket()
    }

    func fallbackWAVData() -> Data? {
        stateQueue.sync {
            guard !capturedPCMData.isEmpty else { return nil }
            return makeWAVData(fromPCM16Mono: capturedPCMData, sampleRate: Int(sampleRate))
        }
    }

    private func makeRealtimeURL() throws -> URL {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")
        var items = [
            URLQueryItem(name: "model_id", value: config.elevenLabsRealtimeModel),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
            URLQueryItem(name: "vad_silence_threshold_secs", value: "0.35"),
            URLQueryItem(name: "min_speech_duration_ms", value: "80"),
            URLQueryItem(name: "min_silence_duration_ms", value: "120"),
            URLQueryItem(name: "include_language_detection", value: "true"),
            URLQueryItem(name: "include_timestamps", value: "false")
        ]
        let language = config.transcriptionLanguageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !language.isEmpty {
            items.append(URLQueryItem(name: "language_code", value: language))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw SpeakFlowError.transcriptionFailed("Could not build the ElevenLabs realtime URL.")
        }
        return url
    }

    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw SpeakFlowError.unableToCaptureAudio
        }

        self.audioEngine = engine
        self.audioConverter = converter
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter,
              let inputFormat,
              let outputFormat
        else {
            return
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = max(1, Int(Double(buffer.frameLength) * ratio) + 32)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(capacity)) else {
            return
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            stateQueue.async {
                self.pendingError = SpeakFlowError.transcriptionFailed("Audio conversion failed: \(conversionError.localizedDescription)")
            }
            return
        }

        guard status == .haveData || status == .inputRanDry,
              convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData
        else {
            return
        }

        let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)
        stateQueue.async {
            self.capturedPCMData.append(data)
        }
        sendAudioFrame(data: data, commit: false)
    }

    private func sendAudioFrame(data: Data, commit: Bool) {
        guard !data.isEmpty || commit else { return }

        sendQueue.async {
            guard let task = self.webSocketTask else { return }

            var payload: [String: Any] = [
                "message_type": "input_audio_chunk",
                "audio_base_64": data.base64EncodedString(),
                "sample_rate": Int(self.sampleRate)
            ]

            self.stateQueue.sync {
                if let previousText = self.previousText, !previousText.isEmpty {
                    payload["previous_text"] = previousText
                    self.previousText = nil
                }
                if commit {
                    payload["commit"] = true
                }
            }

            guard JSONSerialization.isValidJSONObject(payload),
                  let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let text = String(data: jsonData, encoding: .utf8)
            else {
                return
            }

            task.send(.string(text)) { error in
                if let error {
                    self.stateQueue.async {
                        self.pendingError = SpeakFlowError.transcriptionFailed("ElevenLabs send failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func sendFinalizationFrame() throws {
        let silenceFrames = Int(sampleRate * 0.8)
        let silenceBytes = Data(count: silenceFrames * MemoryLayout<Int16>.size)
        sendAudioFrame(data: silenceBytes, commit: true)
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                self.stateQueue.async {
                    if !self.closed {
                        self.pendingError = SpeakFlowError.transcriptionFailed("ElevenLabs receive failed: \(error.localizedDescription)")
                    }
                }
            case .success(let message):
                let text: String
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(decoding: data, as: UTF8.self)
                @unknown default:
                    text = ""
                }

                self.handleIncomingMessage(text)
                self.receiveNextMessage()
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any],
              let type = dict["message_type"] as? String
        else {
            return
        }

        switch type {
        case "partial_transcript":
            let partial = (dict["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !partial.isEmpty else { return }
            stateQueue.async {
                self.partialTranscript = partial
                self.lastPartialAt = Date()
                let snapshot = self.liveTranscriptSnapshot()
                DispatchQueue.main.async {
                    self.onTranscriptChanged?(snapshot)
                }
            }
        case "committed_transcript", "committed_transcript_with_timestamps":
            let segment = (dict["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { return }
            stateQueue.async {
                self.partialTranscript = ""
                if self.committedTranscript.isEmpty {
                    self.committedTranscript = segment
                } else if segment.hasPrefix(self.committedTranscript) {
                    self.committedTranscript = segment
                } else if !self.committedTranscript.hasPrefix(segment) {
                    self.committedTranscript += " " + segment
                }
                self.lastCommittedAt = Date()
                let snapshot = self.liveTranscriptSnapshot()
                DispatchQueue.main.async {
                    self.onTranscriptChanged?(snapshot)
                }
            }
        case "error":
            let message = (dict["error"] as? String) ?? (dict["message"] as? String) ?? "Unknown ElevenLabs realtime error."
            stateQueue.async {
                self.pendingError = SpeakFlowError.transcriptionFailed(message)
            }
        default:
            break
        }
    }

    private func awaitFinalTranscript() async throws -> String {
        let deadline = Date().addingTimeInterval(8)
        var lastStableValue = ""
        var stableSince: Date?

        while Date() < deadline {
            let snapshot = stateQueue.sync { () -> (String, String, Error?, Date?, Date?) in
                (joinedTranscript(), partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines), pendingError, lastCommittedAt, lastPartialAt)
            }

            if let error = snapshot.2 {
                closeSocket()
                throw error
            }

            let transcript = snapshot.0.trimmingCharacters(in: .whitespacesAndNewlines)
            if transcript != lastStableValue {
                lastStableValue = transcript
                stableSince = Date()
            } else if !transcript.isEmpty, let stableSince, Date().timeIntervalSince(stableSince) > 0.55 {
                closeSocket()
                return transcript
            }

            let partial = snapshot.1
            if transcript.isEmpty, !partial.isEmpty, let lastPartialAt = snapshot.4,
               Date().timeIntervalSince(lastPartialAt) > 0.8 {
                closeSocket()
                return partial
            }

            try await Task.sleep(nanoseconds: 150_000_000)
        }

        let fallback = stateQueue.sync {
            let committed = joinedTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
            if !committed.isEmpty {
                return committed
            }
            return partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        closeSocket()
        if !fallback.isEmpty {
            return fallback
        }
        throw SpeakFlowError.transcriptionFailed("No transcript arrived from ElevenLabs.")
    }

    private func joinedTranscript() -> String {
        committedTranscript
            .replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    }

    private func liveTranscriptSnapshot() -> String {
        let committed = joinedTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if committed.isEmpty {
            return partial
        }
        if partial.isEmpty {
            return committed
        }
        return "\(committed) \(partial)"
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        inputFormat = nil
        outputFormat = nil
    }

    private func closeSocket() {
        stateQueue.async {
            self.closed = true
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func makeWAVData(fromPCM16Mono pcmData: Data, sampleRate: Int) -> Data {
        let byteRate = sampleRate * 2
        let blockAlign = 2
        let subchunk2Size = UInt32(pcmData.count)
        let chunkSize = UInt32(36) + subchunk2Size

        var data = Data()
        data.appendUTF8("RIFF")
        data.appendLEUInt32(chunkSize)
        data.appendUTF8("WAVE")
        data.appendUTF8("fmt ")
        data.appendLEUInt32(16)
        data.appendLEUInt16(1)
        data.appendLEUInt16(1)
        data.appendLEUInt32(UInt32(sampleRate))
        data.appendLEUInt32(UInt32(byteRate))
        data.appendLEUInt16(UInt16(blockAlign))
        data.appendLEUInt16(16)
        data.appendUTF8("data")
        data.appendLEUInt32(subchunk2Size)
        data.append(pcmData)
        return data
    }
}

final class WidgetContentView: NSView {
    var onToggle: (() -> Void)?

    enum VisualState {
        case idle
        case active
        case processing
    }

    private let capsuleView = NSVisualEffectView()
    private let borderView = NSView()
    private let glowView = NSView()
    private let idleLineView = NSView()
    private let equalizerContainer = NSView()
    private let equalizerStack = NSStackView()
    private let barViews = (0 ..< 3).map { _ in NSView() }
    private let processingStack = NSStackView()
    private let processingDots = (0 ..< 3).map { _ in NSView() }
    private let backgroundGradientLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    private var barHeightConstraints: [NSLayoutConstraint] = []
    private var processingDotSizeConstraints: [NSLayoutConstraint] = []
    private var animationTimer: Timer?
    private var visualState: VisualState = .idle
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false
    private var processingPhase = 0
    private var equalizerPhase: CGFloat = 0
    private var idleLineWidthConstraint: NSLayoutConstraint?
    private var glowWidthConstraint: NSLayoutConstraint?
    private var glowHeightConstraint: NSLayoutConstraint?

    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var isFlipped: Bool {
        true
    }

    private func setupView() {
        wantsLayer = true

        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.material = .hudWindow
        capsuleView.blendingMode = .withinWindow
        capsuleView.state = .active
        capsuleView.wantsLayer = true
        capsuleView.layer?.cornerRadius = 13
        capsuleView.layer?.cornerCurve = .continuous
        capsuleView.layer?.masksToBounds = true
        capsuleView.layer?.backgroundColor = NSColor.clear.cgColor

        backgroundGradientLayer.colors = [
            NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 0.96).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.98).cgColor
        ]
        backgroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        backgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        backgroundGradientLayer.cornerRadius = 13
        backgroundGradientLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(backgroundGradientLayer)

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.white.withAlphaComponent(0.01).cgColor
        ]
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        sheenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        sheenLayer.cornerRadius = 13
        sheenLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(sheenLayer)

        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 13
        borderView.layer?.cornerCurve = .continuous
        borderView.layer?.borderWidth = 0.7
        borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        borderView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.015).cgColor

        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = 7
        glowView.layer?.cornerCurve = .continuous
        glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor

        idleLineView.translatesAutoresizingMaskIntoConstraints = false
        idleLineView.wantsLayer = true
        idleLineView.layer?.cornerRadius = 2
        idleLineView.layer?.cornerCurve = .continuous
        idleLineView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor

        equalizerStack.translatesAutoresizingMaskIntoConstraints = false
        equalizerStack.orientation = .horizontal
        equalizerStack.alignment = .centerY
        equalizerStack.distribution = .fill
        equalizerStack.spacing = 6.0

        equalizerContainer.translatesAutoresizingMaskIntoConstraints = false
        processingStack.translatesAutoresizingMaskIntoConstraints = false
        processingStack.orientation = .horizontal
        processingStack.alignment = .centerY
        processingStack.distribution = .fillEqually
        processingStack.spacing = 4

        for bar in barViews {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.wantsLayer = true
            bar.layer?.cornerRadius = 1.8
            bar.layer?.cornerCurve = .continuous
            bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
            equalizerStack.addArrangedSubview(bar)

            let width = bar.widthAnchor.constraint(equalToConstant: 6.0)
            let height = bar.heightAnchor.constraint(equalToConstant: 10.0)
            width.isActive = true
            height.isActive = true
            barHeightConstraints.append(height)
        }

        for dot in processingDots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.cornerCurve = .continuous
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            processingStack.addArrangedSubview(dot)

            let width = dot.widthAnchor.constraint(equalToConstant: 6)
            let height = dot.heightAnchor.constraint(equalToConstant: 6)
            width.isActive = true
            height.isActive = true
            processingDotSizeConstraints.append(width)
        }

        addSubview(capsuleView)
        capsuleView.addSubview(borderView)
        capsuleView.addSubview(glowView)
        capsuleView.addSubview(idleLineView)
        capsuleView.addSubview(equalizerContainer)
        equalizerContainer.addSubview(equalizerStack)
        capsuleView.addSubview(processingStack)

        let glowWidthConstraint = glowView.widthAnchor.constraint(equalToConstant: 44)
        let glowHeightConstraint = glowView.heightAnchor.constraint(equalToConstant: 14)
        let idleLineWidthConstraint = idleLineView.widthAnchor.constraint(equalToConstant: 96)
        self.glowWidthConstraint = glowWidthConstraint
        self.glowHeightConstraint = glowHeightConstraint
        self.idleLineWidthConstraint = idleLineWidthConstraint

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: widgetOuterSize.width),
            heightAnchor.constraint(equalToConstant: widgetOuterSize.height),

            capsuleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsuleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsuleView.widthAnchor.constraint(equalToConstant: widgetCapsuleSize.width),
            capsuleView.heightAnchor.constraint(equalToConstant: widgetCapsuleSize.height),

            borderView.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            borderView.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),

            glowView.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            glowWidthConstraint,
            glowHeightConstraint,

            idleLineView.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            idleLineView.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            idleLineWidthConstraint,
            idleLineView.heightAnchor.constraint(equalToConstant: 4),

            equalizerContainer.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            equalizerContainer.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            equalizerContainer.widthAnchor.constraint(equalToConstant: 30),
            equalizerContainer.heightAnchor.constraint(equalToConstant: 16),

            equalizerStack.leadingAnchor.constraint(equalTo: equalizerContainer.leadingAnchor),
            equalizerStack.trailingAnchor.constraint(equalTo: equalizerContainer.trailingAnchor),
            equalizerStack.centerYAnchor.constraint(equalTo: equalizerContainer.centerYAnchor),
            equalizerStack.heightAnchor.constraint(equalToConstant: 14),

            processingStack.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            processingStack.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            processingStack.widthAnchor.constraint(equalToConstant: 40),
            processingStack.heightAnchor.constraint(equalToConstant: 10)
        ])

        apply(state: .idle)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func layout() {
        super.layout()
        backgroundGradientLayer.frame = capsuleView.bounds
        sheenLayer.frame = capsuleView.bounds
    }

    func apply(state: VisualState) {
        visualState = state
        renderVisualState()
    }

    private func renderVisualState() {
        switch visualState {
        case .idle:
            equalizerContainer.isHidden = true
            processingStack.isHidden = true
            idleLineView.isHidden = false
            glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.05 : 0.024).cgColor
            borderView.layer?.borderColor = NSColor.white.withAlphaComponent(isHovered ? 0.18 : 0.11).cgColor
            borderView.layer?.borderWidth = 0.7
            capsuleView.animator().alphaValue = isHovered ? 1.0 : 0.94
            idleLineWidthConstraint?.animator().constant = isHovered ? 108 : 96
            glowWidthConstraint?.animator().constant = isHovered ? 54 : 44
            glowHeightConstraint?.animator().constant = isHovered ? 16 : 14
            stopAnimation()
        case .active:
            equalizerContainer.isHidden = false
            processingStack.isHidden = true
            idleLineView.isHidden = true
            glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            borderView.layer?.borderWidth = 0.7
            capsuleView.animator().alphaValue = 1.0
            glowWidthConstraint?.animator().constant = 48
            glowHeightConstraint?.animator().constant = 15
            startEqualizerAnimation()
        case .processing:
            equalizerContainer.isHidden = true
            processingStack.isHidden = false
            idleLineView.isHidden = true
            glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
            borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            borderView.layer?.borderWidth = 0.7
            capsuleView.animator().alphaValue = 0.98
            glowWidthConstraint?.animator().constant = 46
            glowHeightConstraint?.animator().constant = 15
            startProcessingAnimation()
        }
    }

    private func startEqualizerAnimation() {
        guard animationTimer == nil else { return }
        animateBars()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            self?.animateBars()
        }
    }

    private func startProcessingAnimation() {
        stopAnimation()
        animateProcessingDots()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.24, repeats: true) { [weak self] _ in
            self?.animateProcessingDots()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        let heights: [CGFloat] = [7.0, 13.0, 7.0]
        for (constraint, value) in zip(barHeightConstraints, heights) {
            constraint.animator().constant = value
        }
        for (index, constraint) in processingDotSizeConstraints.enumerated() {
            constraint.animator().constant = index == 1 ? 7.0 : 5.0
            processingDots[index].animator().alphaValue = index == 1 ? 1.0 : 0.55
        }
    }

    private func animateBars() {
        equalizerPhase += 0.65
        for (index, constraint) in barHeightConstraints.enumerated() {
            let distance = abs(index - 1)
            let base: CGFloat
            let swing: CGFloat
            let phaseOffset = CGFloat(distance) * 0.72
            switch distance {
            case 0:
                base = 11.0
                swing = 3.2
            default:
                base = 7.2
                swing = 2.0
            }
            let oscillation = (sin(equalizerPhase + phaseOffset) + 1) * 0.5
            constraint.animator().constant = base + swing * oscillation
        }
    }

    private func animateProcessingDots() {
        processingPhase = (processingPhase + 1) % processingDots.count
        for (index, constraint) in processingDotSizeConstraints.enumerated() {
            let isFocused = index == processingPhase
            constraint.animator().constant = isFocused ? 8.0 : 5.0
            processingDots[index].animator().alphaValue = isFocused ? 1.0 : 0.45
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if visualState == .idle {
            renderVisualState()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if visualState == .idle {
            renderVisualState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let current = NSEvent.mouseLocation
        let deltaX = current.x - dragStartMouseLocation.x
        let deltaY = current.y - dragStartMouseLocation.y
        if abs(deltaX) > 2 || abs(deltaY) > 2 {
            didDrag = true
        }

        let nextOrigin = NSPoint(x: dragStartWindowOrigin.x + deltaX, y: dragStartWindowOrigin.y + deltaY)
        window.setFrameOrigin(nextOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard window != nil else { return }
        if didDrag {
        } else {
            onToggle?()
        }
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ControlCenterWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate, NSControlTextEditingDelegate {
    var onBeginHotkeyCapture: (() -> Void)?
    var onOpenConfigFile: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onUpdateRealtimeModel: ((String) -> Void)?
    var onUpdateBatchModel: ((String) -> Void)?
    var onUpdateCleanupModel: ((String) -> Void)?

    private let providerBadgeLabel = NSTextField(labelWithString: "")
    private let hotkeyBadgeValueLabel = NSTextField(labelWithString: "")
    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let hotkeyHintLabel = NSTextField(labelWithString: "")
    private let heroSubtitleLabel = NSTextField(labelWithString: "")
    private let captureButton = NSButton()
    private let languageValueLabel = NSTextField(labelWithString: "")
    private let cleanupValueLabel = NSTextField(labelWithString: "")
    private let clipboardValueLabel = NSTextField(labelWithString: "")
    private let realtimeModelComboBox = NSComboBox()
    private let batchModelComboBox = NSComboBox()
    private let cleanupModelComboBox = NSComboBox()
    private let dictationsValueLabel = NSTextField(labelWithString: "0")
    private let wordsValueLabel = NSTextField(labelWithString: "0")
    private let charactersValueLabel = NSTextField(labelWithString: "0")
    private let lastUsedValueLabel = NSTextField(labelWithString: "Never")
    private let historyTable = NSTableView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "Dictation history will appear here once you start speaking.")
    private var history: [HistoryEntry] = []
    private var isUpdatingUI = false
    private enum ModelComboRole: Int {
        case realtime = 1
        case batch = 2
        case cleanup = 3
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeakFlow Workspace"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(config: AppConfig, history: [HistoryEntry], stats: UsageStats, isCapturingHotkey: Bool) {
        isUpdatingUI = true
        providerBadgeLabel.stringValue = config.providerName
        hotkeyBadgeValueLabel.stringValue = config.resolvedHotkeyBinding().displayName
        hotkeyValueLabel.stringValue = config.resolvedHotkeyBinding().displayName
        languageValueLabel.stringValue = config.transcriptionLanguageHint.isEmpty ? "Auto detect" : config.transcriptionLanguageHint.uppercased()
        cleanupValueLabel.stringValue = config.cleanupEnabled ? config.cleanupModel : "Disabled"
        clipboardValueLabel.stringValue = config.restoreClipboard ? "Restore after paste" : "Leave latest result"
        realtimeModelComboBox.stringValue = config.elevenLabsRealtimeModel
        batchModelComboBox.stringValue = config.transcriptionModel
        cleanupModelComboBox.stringValue = config.cleanupModel
        hotkeyHintLabel.stringValue = isCapturingHotkey
            ? "Press Fn, Right Command, Right Control, or Ctrl+Option+Space."
            : "Click Change Hotkey, then press the shortcut you want to keep."
        heroSubtitleLabel.stringValue = "Voice keyboard for every macOS app, with reliable dictation history, calmer controls, and a cleaner daily workflow."
        captureButton.title = isCapturingHotkey ? "Listening…" : "Change Hotkey"
        self.history = history
        historyTable.reloadData()
        emptyHistoryLabel.isHidden = !history.isEmpty
        dictationsValueLabel.stringValue = "\(stats.totalDictations)"
        wordsValueLabel.stringValue = "\(stats.totalWords)"
        charactersValueLabel.stringValue = "\(stats.totalCharacters)"
        if let lastUsed = stats.lastDictationAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            lastUsedValueLabel.stringValue = formatter.localizedString(for: lastUsed, relativeTo: Date())
        } else {
            lastUsedValueLabel.stringValue = "Never"
        }
        isUpdatingUI = false
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20

        let headerCard = makeCardView()
        let headerStack = NSStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.distribution = .fill
        headerStack.spacing = 22

        let brandIcon = NSImageView(image: ControlCenterWindowController.makeBrandAppIcon(size: 64))
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.imageScaling = .scaleAxesIndependently
        NSLayoutConstraint.activate([
            brandIcon.widthAnchor.constraint(equalToConstant: 64),
            brandIcon.heightAnchor.constraint(equalToConstant: 64)
        ])

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 8

        let titleLabel = NSTextField(labelWithString: "SpeakFlow Workspace")
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        heroSubtitleLabel.font = .systemFont(ofSize: 14)
        heroSubtitleLabel.textColor = .secondaryLabelColor
        providerBadgeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        providerBadgeLabel.textColor = .secondaryLabelColor

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(heroSubtitleLabel)
        titleStack.addArrangedSubview(providerBadgeLabel)

        let headerBadges = NSStackView()
        headerBadges.orientation = .vertical
        headerBadges.alignment = .trailing
        headerBadges.spacing = 12
        headerBadges.addArrangedSubview(makeBadge(title: "Global Key", valueLabel: hotkeyBadgeValueLabel))

        headerStack.addArrangedSubview(brandIcon)
        headerStack.addArrangedSubview(titleStack)
        headerStack.addArrangedSubview(NSView())
        headerStack.addArrangedSubview(headerBadges)
        headerCard.addSubview(headerStack)

        let metricsRow = NSStackView()
        metricsRow.translatesAutoresizingMaskIntoConstraints = false
        metricsRow.orientation = .horizontal
        metricsRow.alignment = .top
        metricsRow.distribution = .fillEqually
        metricsRow.spacing = 16

        [
            makeMetricCard(title: "Dictations", valueLabel: dictationsValueLabel),
            makeMetricCard(title: "Words", valueLabel: wordsValueLabel),
            makeMetricCard(title: "Characters", valueLabel: charactersValueLabel),
            makeMetricCard(title: "Last Used", valueLabel: lastUsedValueLabel)
        ].forEach { metricsRow.addArrangedSubview($0) }

        let bodySplit = NSStackView()
        bodySplit.translatesAutoresizingMaskIntoConstraints = false
        bodySplit.orientation = .horizontal
        bodySplit.alignment = .top
        bodySplit.distribution = .fill
        bodySplit.spacing = 18

        let controlCard = makeCardView()
        let controlStack = NSStackView()
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.orientation = .vertical
        controlStack.alignment = .leading
        controlStack.spacing = 20

        let controlTitle = sectionTitle("Controls")
        let hotkeySection = NSStackView()
        hotkeySection.orientation = .vertical
        hotkeySection.alignment = .leading
        hotkeySection.spacing = 10
        let hotkeyCaption = NSTextField(labelWithString: "Current shortcut")
        hotkeyCaption.font = .systemFont(ofSize: 12, weight: .medium)
        hotkeyCaption.textColor = .secondaryLabelColor
        hotkeyValueLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        hotkeyHintLabel.font = .systemFont(ofSize: 12)
        hotkeyHintLabel.textColor = .secondaryLabelColor
        captureButton.bezelStyle = .rounded
        captureButton.controlSize = .large
        captureButton.target = self
        captureButton.action = #selector(beginHotkeyCapture)
        let configButton = NSButton(title: "Open Config File", target: self, action: #selector(openConfigFile))
        configButton.bezelStyle = .rounded
        let actionButtons = NSStackView()
        actionButtons.orientation = .horizontal
        actionButtons.alignment = .centerY
        actionButtons.spacing = 10
        actionButtons.addArrangedSubview(captureButton)
        actionButtons.addArrangedSubview(configButton)

        [hotkeyCaption, hotkeyValueLabel, hotkeyHintLabel, actionButtons].forEach { hotkeySection.addArrangedSubview($0) }

        let setupSection = NSStackView()
        setupSection.orientation = .vertical
        setupSection.alignment = .leading
        setupSection.spacing = 10
        setupSection.addArrangedSubview(sectionTitle("Current Setup"))
        setupSection.addArrangedSubview(makeInfoRow(title: "Language Hint", valueLabel: languageValueLabel))
        setupSection.addArrangedSubview(makeInfoRow(title: "Cleanup", valueLabel: cleanupValueLabel))
        setupSection.addArrangedSubview(makeInfoRow(title: "Clipboard", valueLabel: clipboardValueLabel))

        configureModelComboBox(
            realtimeModelComboBox,
            presets: elevenLabsRealtimeModelPresets,
            role: .realtime
        )
        configureModelComboBox(
            batchModelComboBox,
            presets: elevenLabsBatchModelPresets,
            role: .batch
        )
        configureModelComboBox(
            cleanupModelComboBox,
            presets: openAICleanupModelPresets,
            role: .cleanup
        )

        let modelsSection = NSStackView()
        modelsSection.orientation = .vertical
        modelsSection.alignment = .leading
        modelsSection.spacing = 12
        modelsSection.addArrangedSubview(sectionTitle("Model Selection"))
        modelsSection.addArrangedSubview(makeComboRow(title: "Realtime STT", comboBox: realtimeModelComboBox))
        modelsSection.addArrangedSubview(makeComboRow(title: "Batch STT", comboBox: batchModelComboBox))
        modelsSection.addArrangedSubview(makeComboRow(title: "Cleanup", comboBox: cleanupModelComboBox))

        let notesSection = NSStackView()
        notesSection.orientation = .vertical
        notesSection.alignment = .leading
        notesSection.spacing = 8
        let notesTitle = sectionTitle("Operating Notes")
        let notesBody = NSTextField(wrappingLabelWithString: "Short accidental taps are ignored automatically. Silent clips stay quiet. SpeakFlow keeps the widget focused on the screen where you triggered dictation.")
        notesBody.font = .systemFont(ofSize: 12)
        notesBody.textColor = .secondaryLabelColor
        notesBody.maximumNumberOfLines = 0
        notesSection.addArrangedSubview(notesTitle)
        notesSection.addArrangedSubview(notesBody)

        controlStack.addArrangedSubview(controlTitle)
        controlStack.addArrangedSubview(hotkeySection)
        controlStack.addArrangedSubview(setupSection)
        controlStack.addArrangedSubview(modelsSection)
        controlStack.addArrangedSubview(notesSection)
        controlCard.addSubview(controlStack)

        let historyCard = makeCardView()
        let historyStack = NSStackView()
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 16

        let historyHeader = NSStackView()
        historyHeader.orientation = .horizontal
        historyHeader.alignment = .centerY
        historyHeader.spacing = 10
        let historyTitle = sectionTitle("Recent Dictations")
        let historySubtitle = NSTextField(labelWithString: "Latest voice outputs, ready to copy or review.")
        historySubtitle.font = .systemFont(ofSize: 13)
        historySubtitle.textColor = .secondaryLabelColor
        let historyHeaderText = NSStackView()
        historyHeaderText.orientation = .vertical
        historyHeaderText.alignment = .leading
        historyHeaderText.spacing = 2
        historyHeaderText.addArrangedSubview(historyTitle)
        historyHeaderText.addArrangedSubview(historySubtitle)
        historyHeader.addArrangedSubview(historyHeaderText)
        historyHeader.addArrangedSubview(NSView())

        let historyScroll = NSScrollView()
        historyScroll.translatesAutoresizingMaskIntoConstraints = false
        historyScroll.hasVerticalScroller = true
        historyScroll.borderType = .noBorder
        historyScroll.drawsBackground = false
        historyTable.headerView = nil
        historyTable.rowHeight = 58
        historyTable.intercellSpacing = NSSize(width: 0, height: 8)
        historyTable.selectionHighlightStyle = .regular
        historyTable.delegate = self
        historyTable.dataSource = self
        historyTable.backgroundColor = .clear
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.title = "Messages"
        column.resizingMask = .autoresizingMask
        historyTable.addTableColumn(column)
        historyScroll.documentView = historyTable

        emptyHistoryLabel.font = .systemFont(ofSize: 13)
        emptyHistoryLabel.textColor = .secondaryLabelColor

        let historyButtons = NSStackView()
        historyButtons.orientation = .horizontal
        historyButtons.spacing = 10
        let copyButton = NSButton(title: "Copy Selected", target: self, action: #selector(copySelectedHistory))
        copyButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistoryTapped))
        clearButton.bezelStyle = .rounded
        historyButtons.addArrangedSubview(copyButton)
        historyButtons.addArrangedSubview(clearButton)

        historyStack.addArrangedSubview(historyHeader)
        historyStack.addArrangedSubview(emptyHistoryLabel)
        historyStack.addArrangedSubview(historyScroll)
        historyStack.addArrangedSubview(historyButtons)
        historyCard.addSubview(historyStack)

        bodySplit.addArrangedSubview(controlCard)
        bodySplit.addArrangedSubview(historyCard)

        root.addArrangedSubview(headerCard)
        root.addArrangedSubview(metricsRow)
        root.addArrangedSubview(bodySplit)
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -26),

            headerStack.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -24),
            headerStack.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 22),
            headerStack.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -22),

            controlCard.widthAnchor.constraint(equalToConstant: 328),

            controlStack.leadingAnchor.constraint(equalTo: controlCard.leadingAnchor, constant: 22),
            controlStack.trailingAnchor.constraint(equalTo: controlCard.trailingAnchor, constant: -22),
            controlStack.topAnchor.constraint(equalTo: controlCard.topAnchor, constant: 22),
            controlStack.bottomAnchor.constraint(lessThanOrEqualTo: controlCard.bottomAnchor, constant: -22),

            historyStack.leadingAnchor.constraint(equalTo: historyCard.leadingAnchor, constant: 22),
            historyStack.trailingAnchor.constraint(equalTo: historyCard.trailingAnchor, constant: -22),
            historyStack.topAnchor.constraint(equalTo: historyCard.topAnchor, constant: 22),
            historyStack.bottomAnchor.constraint(equalTo: historyCard.bottomAnchor, constant: -22),

            historyScroll.widthAnchor.constraint(equalTo: historyStack.widthAnchor),
            historyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),

            bodySplit.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }

    private func makeCardView() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        return card
    }

    private func makeMetricCard(title: String, valueLabel: NSTextField) -> NSView {
        let card = makeCardView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func makeInfoRow(title: String, valueLabel: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func configureModelComboBox(_ comboBox: NSComboBox, presets: [String], role: ModelComboRole) {
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        comboBox.isEditable = true
        comboBox.usesDataSource = false
        comboBox.addItems(withObjectValues: presets)
        comboBox.completes = true
        comboBox.delegate = self
        comboBox.target = self
        comboBox.action = #selector(modelComboSelectionChanged(_:))
        comboBox.tag = role.rawValue
        comboBox.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        NSLayoutConstraint.activate([
            comboBox.widthAnchor.constraint(equalToConstant: 170)
        ])
    }

    private func makeComboRow(title: String, comboBox: NSComboBox) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(comboBox)
        return row
    }

    @objc
    private func modelComboSelectionChanged(_ sender: NSComboBox) {
        commitModelSelection(for: sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let comboBox = obj.object as? NSComboBox else { return }
        commitModelSelection(for: comboBox)
    }

    private func commitModelSelection(for comboBox: NSComboBox) {
        guard !isUpdatingUI else { return }
        let value = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let role = ModelComboRole(rawValue: comboBox.tag) else { return }

        switch role {
        case .realtime:
            onUpdateRealtimeModel?(value)
        case .batch:
            onUpdateBatchModel?(value)
        case .cleanup:
            onUpdateCleanupModel?(value)
        }
    }

    private func makeBadge(title: String, valueLabel: NSTextField) -> NSView {
        let wrapper = makeCardView()
        wrapper.layer?.cornerRadius = 12
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10)
        ])
        return wrapper
    }

    private static func makeBrandAppIcon(size: CGFloat) -> NSImage {
        if let bundled = loadBundledAppIconImage() {
            bundled.size = NSSize(width: size, height: size)
            return bundled
        }
        return makePulseImage(
            size: NSSize(width: size, height: size),
            color: NSColor.white.withAlphaComponent(0.96),
            backgroundColor: NSColor(calibratedWhite: 0.08, alpha: 1.0),
            template: false
        )
    }

    @objc
    private func beginHotkeyCapture() {
        guard !isUpdatingUI else { return }
        onBeginHotkeyCapture?()
    }

    @objc
    private func openConfigFile() {
        onOpenConfigFile?()
    }

    @objc
    private func clearHistoryTapped() {
        onClearHistory?()
    }

    @objc
    private func copySelectedHistory() {
        let row = historyTable.selectedRow
        guard history.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history[row].text, forType: .string)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard history.indices.contains(row) else { return nil }
        let entry = history[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 12
        cell.layer?.cornerCurve = .continuous
        cell.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor

        let titleTag = 101
        let subtitleTag = 102
        let titleField: NSTextField
        let subtitleField: NSTextField

        if let existingTitle = cell.viewWithTag(titleTag) as? NSTextField,
           let existingSubtitle = cell.viewWithTag(subtitleTag) as? NSTextField {
            titleField = existingTitle
            subtitleField = existingSubtitle
        } else {
            let title = NSTextField(labelWithString: "")
            title.tag = titleTag
            title.translatesAutoresizingMaskIntoConstraints = false
            title.font = .systemFont(ofSize: 12, weight: .medium)
            title.textColor = .secondaryLabelColor

            let subtitle = NSTextField(labelWithString: "")
            subtitle.tag = subtitleTag
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            subtitle.font = .systemFont(ofSize: 14)
            subtitle.lineBreakMode = .byTruncatingTail

            cell.addSubview(title)
            cell.addSubview(subtitle)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 10),
                subtitle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                subtitle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
                subtitle.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -10)
            ])
            titleField = title
            subtitleField = subtitle
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        titleField.stringValue = "\(formatter.string(from: entry.createdAt))  ·  \(entry.provider)"
        subtitleField.stringValue = entry.text
        return cell
    }
}

final class SpeakFlowApp: NSObject, NSApplicationDelegate {
    private enum State {
        case idle
        case recording
        case transcribing
    }

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
    private var state: State = .idle {
        didSet {
            Task { @MainActor in
                self.refreshUI()
            }
        }
    }

    private var statusItem: NSStatusItem!
    private var widgetWindows: [WidgetPanel] = []
    private var widgetViews: [WidgetContentView] = []
    private let menu = NSMenu()
    private let statusSummaryItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let hotKeyInfoItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
    private lazy var toggleRecordingItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleRecordingFromMenu), keyEquivalent: "")
    private lazy var pasteLastItem = NSMenuItem(title: "Paste Last Result Again", action: #selector(pasteLastResult), keyEquivalent: "")
    private lazy var copyLastItem = NSMenuItem(title: "Copy Last Result", action: #selector(copyLastResult), keyEquivalent: "")
    private lazy var controlCenterItem = NSMenuItem(title: "Open Settings & History…", action: #selector(openControlCenter), keyEquivalent: ",")
    private lazy var openConfigItem = NSMenuItem(title: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
    private lazy var revealSupportItem = NSMenuItem(title: "Reveal Support Folder", action: #selector(revealSupportFolder), keyEquivalent: "")
    private lazy var reloadConfigItem = NSMenuItem(title: "Reload Settings", action: #selector(reloadConfig), keyEquivalent: "")
    private lazy var resetWidgetItem = NSMenuItem(title: "Reset Widget Position", action: #selector(resetWidgetPosition), keyEquivalent: "")
    private lazy var quitItem = NSMenuItem(title: "Quit SpeakFlow", action: #selector(quitApp), keyEquivalent: "q")

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
            buildMenu()
            buildWidgets()
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
    private func revealSupportFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([configStore.supportDirectoryURL])
    }

    @MainActor
    @objc
    private func reloadConfig() {
        do {
            config = try configStore.load()
            registerHotKey()
            refreshUI()
            controlCenterWindowController?.update(config: config, history: history, stats: stats, isCapturingHotkey: isCapturingHotkey)
        } catch {
            presentError(message: "Config reload failed.\n\(error.localizedDescription)")
        }
    }

    @MainActor
    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

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

    private func menuSectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeStatusBarIcon(for state: State) -> NSImage {
        let image: NSImage
        switch state {
        case .idle:
            image = makePulseImage(size: NSSize(width: 18, height: 18), color: .labelColor, template: true)
        case .recording:
            image = makePulseImage(size: NSSize(width: 18, height: 18), color: .controlAccentColor, template: false)
        case .transcribing:
            image = makePulseImage(size: NSSize(width: 18, height: 18), color: .secondaryLabelColor, template: true)
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

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
        UserDefaults.standard.removeObject(forKey: widgetOriginXKey)
        UserDefaults.standard.removeObject(forKey: widgetOriginYKey)
        positionWidgetWindows(animated: true)
    }

    @MainActor
    @objc
    private func handleScreenParametersChanged() {
        buildWidgets()
        refreshUI()
    }

    @MainActor
    private func buildMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        statusSummaryItem.isEnabled = false
        hotKeyInfoItem.isEnabled = false
        toggleRecordingItem.target = self
        pasteLastItem.target = self
        copyLastItem.target = self
        controlCenterItem.target = self
        openConfigItem.target = self
        revealSupportItem.target = self
        reloadConfigItem.target = self
        quitItem.target = self

        menu.removeAllItems()
        menu.addItem(statusSummaryItem)
        menu.addItem(hotKeyInfoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleRecordingItem)
        menu.addItem(controlCenterItem)
        menu.addItem(pasteLastItem)
        menu.addItem(copyLastItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openConfigItem)
        menu.addItem(resetWidgetItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @MainActor
    private func buildWidgets() {
        widgetWindows.forEach { $0.orderOut(nil) }
        widgetWindows.removeAll()
        widgetViews.removeAll()

        for screen in NSScreen.screens {
            let frame = defaultWidgetFrame(on: screen)
            let window = WidgetPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            let view = WidgetContentView(frame: NSRect(origin: .zero, size: frame.size))
            view.onToggle = { [weak self] in
                self?.toggleRecording()
            }
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.ignoresMouseEvents = false
            window.isMovable = false
            window.contentView = view
            window.orderFrontRegardless()
            widgetWindows.append(window)
            widgetViews.append(view)
            debugLog("Widget built at frame \(NSStringFromRect(frame))")
        }
        positionWidgetWindows(animated: false)
    }

    @MainActor
    private func restoredWidgetFrame(forceDefault: Bool = false) -> NSRect {
        let size = widgetOuterSize
        let defaults = UserDefaults.standard
        if !forceDefault,
           defaults.object(forKey: widgetOriginXKey) != nil,
           defaults.object(forKey: widgetOriginYKey) != nil {
            let x = defaults.double(forKey: widgetOriginXKey)
            let y = defaults.double(forKey: widgetOriginYKey)
            let restored = NSRect(origin: NSPoint(x: x, y: y), size: size)
            if screenVisibleFrame(containing: restored) != nil {
                return restored
            }
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 34
        )
        return NSRect(origin: origin, size: size)
    }

    private func storeWidgetOrigin(_ origin: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: widgetOriginXKey)
        defaults.set(origin.y, forKey: widgetOriginYKey)
    }

    private func screenVisibleFrame(containing frame: NSRect) -> NSRect? {
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let intersection = visible.intersection(frame)
            if !intersection.isNull, intersection.width >= 140, intersection.height >= 32 {
                return visible
            }
        }
        return nil
    }

    private func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen
        }
        return nil
    }

    private func defaultWidgetFrame(on screen: NSScreen) -> NSRect {
        let size = widgetOuterSize
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 34
        )
        return NSRect(origin: origin, size: size)
    }

    @MainActor
    private func positionWidgetWindows(animated: Bool) {
        let screens = NSScreen.screens
        if screens.count != widgetWindows.count {
            buildWidgets()
            return
        }

        for (window, screen) in zip(widgetWindows, screens) {
            let targetFrame = defaultWidgetFrame(on: screen)
            window.setFrame(targetFrame, display: true, animate: animated)
            debugLog("Widget moved to screen frame \(NSStringFromRect(targetFrame))")
        }
        panelBringToFront()
    }

    @MainActor
    private func moveWidgetToPreferredScreen(animated: Bool) {
        positionWidgetWindows(animated: animated)
    }

    @MainActor
    private func panelBringToFront() {
        for window in widgetWindows {
            window.orderFrontRegardless()
        }
    }

    @MainActor
    private func refreshUI() {
        debugLog("UI refreshed for state=\(String(describing: state)) hotkey=\(config.resolvedHotkeyBinding().rawValue)")
        switch state {
        case .idle:
            toggleRecordingItem.title = "Start Dictation"
            statusSummaryItem.title = "Ready to dictate"
        case .recording:
            toggleRecordingItem.title = "Stop Dictation"
            statusSummaryItem.title = "Listening now"
        case .transcribing:
            toggleRecordingItem.title = "Processing Audio..."
            statusSummaryItem.title = "Finalizing transcript"
        }

        toggleRecordingItem.isEnabled = state != .transcribing
        pasteLastItem.isEnabled = !lastOutputText.isEmpty
        copyLastItem.isEnabled = !lastOutputText.isEmpty
        hotKeyInfoItem.title = "Hotkey: \(config.resolvedHotkeyBinding().displayName)"

        if let button = statusItem.button {
            button.image = makeStatusBarIcon(for: state)
            button.toolTip = tooltipText()
        }

        let widgetState: WidgetContentView.VisualState
        switch state {
        case .idle:
            widgetState = .idle
        case .recording:
            widgetState = .active
        case .transcribing:
            widgetState = .processing
        }
        widgetViews.forEach { $0.apply(state: widgetState) }
    }

    @MainActor
    private func tooltipText() -> String {
        switch state {
        case .idle:
            return "\(appDisplayName)\nReady to dictate"
        case .recording:
            return "\(appDisplayName)\nRecording..."
        case .transcribing:
            return "\(appDisplayName)\nTranscribing and cleaning text..."
        }
    }

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

        var hotKeyID = EventHotKeyID(signature: OSType(0x5350464C), id: 1)
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
                Task { @MainActor in
                    if granted {
                        self.startRecording()
                    } else {
                        self.presentError(message: "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone.")
                    }
                }
            }
        case .denied, .restricted:
            presentError(message: "Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone.")
        @unknown default:
            presentError(message: "Microphone permission is unavailable on this system.")
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

        let visibleWidgets = widgetWindows.filter(\.isVisible)
        visibleWidgets.forEach { $0.orderOut(nil) }

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
                    visibleWidgets.forEach { $0.orderFrontRegardless() }
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

let app = NSApplication.shared
let delegate = SpeakFlowApp()
app.delegate = delegate
app.run()
