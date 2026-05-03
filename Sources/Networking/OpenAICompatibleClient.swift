import AVFoundation
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
    let session: NetworkSession
    let environment: [String: String]
    private let singleUploadSoftLimitBytes = 22 * 1024 * 1024
    private let chunkDurationSeconds: Double = 8 * 60
    private let chunkStagingDirectoryURL: URL

    init(
        config: AppConfig,
        session: NetworkSession = URLSession.shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.config = config
        self.session = session
        self.environment = environment
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.chunkStagingDirectoryURL = appSupport
            .appendingPathComponent(appDisplayName, isDirectory: true)
            .appendingPathComponent("transcription-chunks", isDirectory: true)
    }

    private func endpointURL(_ suffix: String) throws -> URL {
        let trimmed = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + suffix) else {
            throw SpeakFlowError.invalidBaseURL(config.baseURL)
        }
        return url
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        guard let apiKey = config.resolvedOpenAIAPIKey(environment: environment) else {
            throw SpeakFlowError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        return request
    }

    func transcribe(audioFileURL: URL, modelOverride: String? = nil) async throws -> String {
        let fileExtension = audioFileURL.pathExtension.isEmpty ? "m4a" : audioFileURL.pathExtension.lowercased()
        let mimeType = mimeType(for: fileExtension)
        let fileSizeBytes = (try? audioFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if fileSizeBytes > singleUploadSoftLimitBytes {
            return try await transcribeInChunks(audioFileURL: audioFileURL, modelOverride: modelOverride)
        }

        do {
            let data = try Data(contentsOf: audioFileURL)
            return try await transcribe(
                audioData: data,
                mimeType: mimeType,
                fileExtension: fileExtension,
                modelOverride: modelOverride
            )
        } catch {
            if shouldRetryTranscriptionByChunking(error: error) {
                return try await transcribeInChunks(audioFileURL: audioFileURL, modelOverride: modelOverride)
            }
            throw error
        }
    }

    func transcribe(
        audioData: Data,
        mimeType: String,
        fileExtension: String,
        modelOverride: String? = nil
    ) async throws -> String {
        let url = try endpointURL("/audio/transcriptions")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"

        var multipart = MultipartFormData()
        let model = resolvedTranscriptionModel(modelOverride)
        multipart.addField(name: "model", value: model)
        multipart.addField(name: "prompt", value: config.resolvedTranscriptionPrompt())
        multipart.addField(name: "response_format", value: "text")
        let languageHint = config.transcriptionLanguageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !languageHint.isEmpty {
            multipart.addField(name: "language", value: languageHint)
        }
        multipart.addFile(name: "file", filename: "speakflow-transcription.\(fileExtension)", mimeType: mimeType, data: audioData)

        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.finalized()

        let (responseData, response) = try await session.data(for: request)
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

        guard config.resolvedOpenAIAPIKey(environment: environment) != nil else {
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

        let (responseData, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: responseData, failureCase: SpeakFlowError.cleanupFailed)

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
        let cleaned = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleaned.isEmpty {
            throw SpeakFlowError.cleanupFailed("The cleanup model returned an empty result.")
        }
        return cleaned
    }

    func summarize(text: String) async throws -> String {
        guard config.resolvedOpenAIAPIKey(environment: environment) != nil else {
            throw SpeakFlowError.cleanupFailed("An OpenAI API key is required to summarize recordings.")
        }

        let url = try endpointURL("/chat/completions")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatCompletionRequest(
            model: config.cleanupModel,
            messages: [
                .init(
                    role: "system",
                    content: """
You summarize recorded meeting notes and spoken monologues.
Write a concise, useful summary in the same language as the transcript.
Preserve key decisions, tasks, and named entities.
Use plain text only with short paragraphs or short bullet-like lines.
"""
                ),
                .init(role: "user", content: text)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: responseData, failureCase: SpeakFlowError.cleanupFailed)

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
        let summary = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if summary.isEmpty {
            throw SpeakFlowError.cleanupFailed("The summary model returned an empty result.")
        }
        return summary
    }

    private func resolvedTranscriptionModel(_ override: String?) -> String {
        let candidate = (override ?? config.transcriptionModel).trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty {
            return candidate
        }
        return openAITranscriptionFallbackModel
    }

    private func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "ogg":
            return "audio/ogg"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private func shouldRetryTranscriptionByChunking(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let markers = [
            "http 400",
            "invalid_request_error",
            "invalid_value",
            "audio file might be corrupted or unsupported",
            "maximum content size",
            "size limit",
            "too large",
            "file exceeds"
        ]
        return markers.contains { message.contains($0) }
    }

    private func transcribeInChunks(audioFileURL: URL, modelOverride: String?) async throws -> String {
        let asset = AVURLAsset(url: audioFileURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw SpeakFlowError.transcriptionFailed("Could not determine audio duration for chunked transcription.")
        }

        try FileManager.default.createDirectory(at: chunkStagingDirectoryURL, withIntermediateDirectories: true)
        let sessionID = UUID().uuidString
        var cursor: Double = 0
        var index = 0
        var transcripts: [String] = []
        var chunkURLs: [URL] = []

        while cursor < durationSeconds {
            let segmentDuration = min(chunkDurationSeconds, durationSeconds - cursor)
            let chunkURL = chunkStagingDirectoryURL
                .appendingPathComponent("session-\(sessionID)-chunk-\(index + 1)")
                .appendingPathExtension("m4a")
            chunkURLs.append(chunkURL)

            do {
                try await exportChunk(asset: asset, startSeconds: cursor, durationSeconds: segmentDuration, outputURL: chunkURL)
                let chunkData = try Data(contentsOf: chunkURL)
                let chunkTranscript = try await transcribe(
                    audioData: chunkData,
                    mimeType: "audio/mp4",
                    fileExtension: "m4a",
                    modelOverride: modelOverride
                )
                let trimmed = chunkTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    transcripts.append(trimmed)
                }
            } catch {
                throw SpeakFlowError.transcriptionFailed(
                    "Chunk \(index + 1) transcription failed: \(error.localizedDescription)\n" +
                    "Chunks were preserved in \(chunkStagingDirectoryURL.path)."
                )
            }

            cursor += segmentDuration
            index += 1
        }

        let combined = transcripts.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty {
            throw SpeakFlowError.transcriptionFailed("Chunked transcription returned an empty result.")
        }

        for chunkURL in chunkURLs {
            try? FileManager.default.removeItem(at: chunkURL)
        }
        return combined
    }

    private func exportChunk(
        asset: AVURLAsset,
        startSeconds: Double,
        durationSeconds: Double,
        outputURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeakFlowError.transcriptionFailed("Could not create export session for chunked transcription.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    let message = exportSession.error?.localizedDescription ?? "Unknown export error."
                    continuation.resume(throwing: SpeakFlowError.transcriptionFailed("Audio chunk export failed: \(message)"))
                case .cancelled:
                    continuation.resume(throwing: SpeakFlowError.transcriptionFailed("Audio chunk export was cancelled."))
                default:
                    let message = exportSession.error?.localizedDescription ?? "Chunk export did not complete."
                    continuation.resume(throwing: SpeakFlowError.transcriptionFailed("Audio chunk export failed: \(message)"))
                }
            }
        }
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
