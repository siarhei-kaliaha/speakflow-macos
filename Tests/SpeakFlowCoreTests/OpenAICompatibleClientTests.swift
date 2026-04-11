import Foundation
import XCTest
@testable import SpeakFlowCore

final class OpenAICompatibleClientTests: XCTestCase {
    func testCleanupReturnsOriginalTextWhenDisabled() async throws {
        var config = AppConfig.default()
        config.cleanupEnabled = false
        let client = OpenAICompatibleClient(config: config, session: MockNetworkSession(), environment: [:])

        let result = try await client.cleanup(text: "raw text")

        XCTAssertEqual(result, "raw text")
    }

    func testCleanupBuildsAuthorizedRequestAndParsesResponse() async throws {
        var config = AppConfig.default()
        config.apiKey = "test-key"
        config.cleanupModel = "gpt-5.4-mini"

        let responseBody = """
        {
          "choices": [
            { "message": { "content": "Cleaned text." } }
          ]
        }
        """.data(using: .utf8)!
        let session = MockNetworkSession(responseData: responseBody)
        let client = OpenAICompatibleClient(config: config, session: session, environment: [:])

        let result = try await client.cleanup(text: "messy text")

        XCTAssertEqual(result, "Cleaned text.")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertTrue(String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8)?.contains("\"model\":\"gpt-5.4-mini\"") == true)
    }

    func testCleanupThrowsOnEmptyResponseText() async {
        var config = AppConfig.default()
        config.apiKey = "test-key"

        let responseBody = """
        {
          "choices": [
            { "message": { "content": "   " } }
          ]
        }
        """.data(using: .utf8)!
        let session = MockNetworkSession(responseData: responseBody)
        let client = OpenAICompatibleClient(config: config, session: session, environment: [:])

        await XCTAssertThrowsErrorAsync(try await client.cleanup(text: "messy")) { error in
            XCTAssertEqual(error.localizedDescription, SpeakFlowError.cleanupFailed("The cleanup model returned an empty result.").localizedDescription)
        }
    }

    func testTranscribeBuildsMultipartBodyWithPromptAndLanguageHint() async throws {
        var config = AppConfig.default()
        config.apiKey = "test-key"
        config.transcriptionLanguageHint = "en"
        config.customVocabulary = ["OpenAI"]

        let tempDirectory = try makeTempDirectory()
        let audioURL = tempDirectory.appendingPathComponent("clip.m4a")
        try Data("audio".utf8).write(to: audioURL)

        let session = MockNetworkSession(responseData: Data("Transcript".utf8))
        let client = OpenAICompatibleClient(config: config, session: session, environment: [:])

        let transcript = try await client.transcribe(audioFileURL: audioURL)
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""

        XCTAssertEqual(transcript, "Transcript")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("scribe_v2"))
        XCTAssertTrue(body.contains("name=\"language\""))
        XCTAssertTrue(body.contains("en"))
        XCTAssertTrue(body.contains("Prefer these spellings when they match the audio: OpenAI"))
    }

    func testMultipartFormDataFinalizesWithClosingBoundary() {
        var multipart = MultipartFormData()
        multipart.addField(name: "model", value: "gpt")
        multipart.addFile(name: "file", filename: "clip.wav", mimeType: "audio/wav", data: Data("abc".utf8))

        let result = String(data: multipart.finalized(), encoding: .utf8) ?? ""

        XCTAssertTrue(result.contains("Content-Disposition: form-data; name=\"model\""))
        XCTAssertTrue(result.contains("filename=\"clip.wav\""))
        XCTAssertTrue(result.contains("--\(multipart.boundary)--"))
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
