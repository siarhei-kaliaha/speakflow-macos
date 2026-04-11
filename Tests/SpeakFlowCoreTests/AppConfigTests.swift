import XCTest
@testable import SpeakFlowCore

final class AppConfigTests: XCTestCase {
    func testDefaultConfigUsesExpectedProviderAndHotkey() {
        let config = AppConfig.default()

        XCTAssertEqual(config.providerName, "ElevenLabs realtime + OpenAI cleanup")
        XCTAssertEqual(config.resolvedHotkeyBinding(), .fn)
        XCTAssertEqual(config.cleanupModel, "gpt-5.1")
    }

    func testDecodingMissingKeysFallsBackToDefaults() throws {
        let data = """
        {
          "providerName": "Custom Provider"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.providerName, "Custom Provider")
        XCTAssertEqual(decoded.baseURL, AppConfig.default().baseURL)
        XCTAssertEqual(decoded.transcriptionModel, AppConfig.default().transcriptionModel)
        XCTAssertEqual(decoded.resolvedHotkeyBinding(), .fn)
    }

    func testResolvedAPIKeysPreferInlineValuesThenEnvironment() {
        var config = AppConfig.default()
        config.apiKey = " inline-openai "
        config.elevenLabsAPIKey = " inline-eleven "

        XCTAssertEqual(
            config.resolvedOpenAIAPIKey(environment: ["OPENAI_API_KEY": "env-openai"]),
            "inline-openai"
        )
        XCTAssertEqual(
            config.resolvedElevenLabsAPIKey(environment: ["ELEVENLABS_API_KEY": "env-eleven"]),
            "inline-eleven"
        )

        config.apiKey = ""
        config.elevenLabsAPIKey = ""

        XCTAssertEqual(
            config.resolvedOpenAIAPIKey(environment: ["OPENAI_API_KEY": " env-openai "]),
            "env-openai"
        )
        XCTAssertEqual(
            config.resolvedElevenLabsAPIKey(environment: ["ELEVENLABS_API_KEY": " env-eleven "]),
            "env-eleven"
        )
        XCTAssertNil(config.resolvedOpenAIAPIKey(environment: [:]))
        XCTAssertNil(config.resolvedElevenLabsAPIKey(environment: [:]))
    }

    func testResolvedPromptAppendsVocabularySection() {
        var config = AppConfig.default()
        config.transcriptionPrompt = "Base prompt"
        config.customVocabulary = ["OpenAI", "macOS"]

        let prompt = config.resolvedTranscriptionPrompt()

        XCTAssertTrue(prompt.contains("Base prompt"))
        XCTAssertTrue(prompt.contains("Prefer these spellings when they match the audio: OpenAI, macOS"))
    }

    func testResolvedHotkeyFallsBackForUnknownValue() {
        var config = AppConfig.default()
        config.hotkeyBinding = "unknown"

        XCTAssertEqual(config.resolvedHotkeyBinding(), .fn)
    }
}
