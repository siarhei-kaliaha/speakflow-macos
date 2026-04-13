import AVFoundation
import Foundation
final class ElevenLabsRealtimeTranscriber {
    var onTranscriptChanged: ((String) -> Void)?
    var onAudioLevelsChanged: (([CGFloat]) -> Void)?

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
    private var sessionStarted = false
    private var pendingChunks: [Data] = []

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
        stateQueue.sync {
            self.closed = false
            self.pendingError = nil
            self.sessionStarted = false
            self.pendingChunks.removeAll(keepingCapacity: true)
            self.capturedPCMData.removeAll(keepingCapacity: true)
            self.committedTranscript = ""
            self.partialTranscript = ""
        }
        task.resume()
        receiveNextMessage()
        try startAudioEngine()
    }

    func finish() async throws -> String {
        try await waitForSessionStartIfNeeded()
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

        let liveLevels = makeLiveLevels(from: buffer, bands: 25)
        if !liveLevels.isEmpty {
            DispatchQueue.main.async {
                self.onAudioLevelsChanged?(liveLevels)
            }
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
            if self.sessionStarted {
                self.sendAudioFrame(data: data, commit: false)
            } else {
                self.pendingChunks.append(data)
            }
        }
    }

    private func makeLiveLevels(from buffer: AVAudioPCMBuffer, bands: Int) -> [CGFloat] {
        guard bands > 0 else { return [] }
        let samples = extractSamples(from: buffer)
        guard !samples.isEmpty else { return Array(repeating: 0, count: bands) }

        let segmentLength = max(1, samples.count / bands)
        var levels: [CGFloat] = []
        levels.reserveCapacity(bands)

        for bandIndex in 0..<bands {
            let start = bandIndex * segmentLength
            let end = min(samples.count, bandIndex == bands - 1 ? samples.count : start + segmentLength)
            guard start < end else {
                levels.append(0)
                continue
            }

            let slice = samples[start..<end]
            var sumSquares: Float = 0
            for sample in slice {
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(slice.count))
            let boosted = min(1.0, pow(CGFloat(rms) * 6.8, 0.62))
            levels.append(boosted)
        }

        return levels
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return [] }
            let source = channelData[0]
            return Array(UnsafeBufferPointer(start: source, count: frameLength))
        case .pcmFormatFloat64:
            guard let channelData = buffer.floatChannelData else { return [] }
            let source = channelData[0]
            return Array(UnsafeBufferPointer(start: source, count: frameLength)).map { Float($0) }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return [] }
            let source = channelData[0]
            let raw = Array(UnsafeBufferPointer(start: source, count: frameLength))
            return raw.map { Float($0) / Float(Int16.max) }
        case .pcmFormatInt32:
            guard let channelData = buffer.int32ChannelData else { return [] }
            let source = channelData[0]
            let raw = Array(UnsafeBufferPointer(start: source, count: frameLength))
            return raw.map { Float($0) / Float(Int32.max) }
        default:
            return []
        }
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
                        if self.closed {
                            return
                        }
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
        case "session_started":
            stateQueue.async {
                self.sessionStarted = true
                let buffered = self.pendingChunks
                self.pendingChunks.removeAll(keepingCapacity: true)
                self.sendQueue.async {
                    for chunk in buffered {
                        self.sendAudioFrame(data: chunk, commit: false)
                    }
                }
            }
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

    private func waitForSessionStartIfNeeded() async throws {
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            let snapshot = stateQueue.sync { (sessionStarted, pendingError, closed) }
            if let error = snapshot.1 {
                throw error
            }
            if snapshot.0 || snapshot.2 {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func closeSocket() {
        stateQueue.async {
            self.closed = true
            self.sessionStarted = false
            self.pendingChunks.removeAll(keepingCapacity: true)
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
