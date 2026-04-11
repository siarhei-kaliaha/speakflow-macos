import Foundation
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

