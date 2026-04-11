import Foundation
import XCTest
@testable import SpeakFlowCore

final class ElevenLabsBatchTranscriberClientTests: XCTestCase {
    func testTranscribeBuildsBatchRequestAndParsesResponse() async throws {
        var config = AppConfig.default()
        config.elevenLabsAPIKey = "eleven-key"
        config.transcriptionLanguageHint = "ru"
        config.customVocabulary = ["ChatGPT"]

        let responseBody = #"{"text":"  Final transcript  "}"#.data(using: .utf8)!
        let session = MockNetworkSession(responseData: responseBody)
        let client = ElevenLabsBatchTranscriberClient(config: config, session: session, environment: [:])

        let result = try await client.transcribe(audioData: Data("wav".utf8))
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""

        XCTAssertEqual(result, "Final transcript")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "xi-api-key"), "eleven-key")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertTrue(body.contains("name=\"model_id\""))
        XCTAssertTrue(body.contains("scribe_v2"))
        XCTAssertTrue(body.contains("language_code"))
        XCTAssertTrue(body.contains("ru"))
        XCTAssertTrue(body.contains("Prefer these spellings when they match the audio: ChatGPT"))
    }

    func testTranscribeThrowsForMissingAPIKey() async {
        let config = AppConfig.default()
        let client = ElevenLabsBatchTranscriberClient(config: config, session: MockNetworkSession(), environment: [:])

        await XCTAssertThrowsErrorAsync(try await client.transcribe(audioData: Data())) { error in
            XCTAssertTrue(error.localizedDescription.contains("elevenLabsAPIKey"))
        }
    }

    func testTranscribeThrowsForHTTPFailure() async {
        var config = AppConfig.default()
        config.elevenLabsAPIKey = "eleven-key"

        let session = MockNetworkSession(
            responseData: Data("bad request".utf8),
            response: HTTPURLResponse(
                url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let client = ElevenLabsBatchTranscriberClient(config: config, session: session, environment: [:])

        await XCTAssertThrowsErrorAsync(try await client.transcribe(audioData: Data("wav".utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTTP 400"))
        }
    }
}
