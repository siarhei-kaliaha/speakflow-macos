import Foundation
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

