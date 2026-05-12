import Foundation

struct WidgetScreenPosition: Codable, Equatable {
    var normalizedCenterX: Double
    var normalizedCenterY: Double
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
    var widgetPositionsByScreen: [String: WidgetScreenPosition]

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
        case widgetPositionsByScreen
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
            hotkeyBinding: HotkeyBinding.fn.rawValue,
            widgetPositionsByScreen: [:]
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
        hotkeyBinding: String,
        widgetPositionsByScreen: [String: WidgetScreenPosition]
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
        self.widgetPositionsByScreen = widgetPositionsByScreen
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
        widgetPositionsByScreen = try container.decodeIfPresent([String: WidgetScreenPosition].self, forKey: .widgetPositionsByScreen) ?? defaults.widgetPositionsByScreen
    }

    func resolvedHotkeyBinding() -> HotkeyBinding {
        HotkeyBinding(rawValue: hotkeyBinding) ?? .fn
    }

    func resolvedOpenAIAPIKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let inline = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        if let env = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        return nil
    }

    func resolvedElevenLabsAPIKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let inline = elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        if let env = environment["ELEVENLABS_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
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
