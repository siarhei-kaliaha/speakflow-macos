import Foundation

final class ConfigStore {
    let supportDirectoryURL: URL
    let configURL: URL

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            supportDirectoryURL = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            supportDirectoryURL = appSupport.appendingPathComponent(appDisplayName, isDirectory: true)
        }
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

struct CaptureRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: CaptureKind
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let provider: String
    let transcriptionModel: String
    let cleanupModel: String?
    let rawTranscript: String
    let finalText: String
    var summary: String?
    let title: String
    let status: CaptureStatus

    var createdAt: Date { endedAt }
    var characters: Int { finalText.count }
    var words: Int {
        finalText.split { $0.isWhitespace || $0.isNewline }.count
    }

    var summaryStatusText: String {
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Ready"
        }
        return kind == .recordingSession ? "Not generated" : "Not applicable"
    }
}

struct UsageStats: Codable {
    var totalDictations: Int
    var totalRecordings: Int
    var totalCharacters: Int
    var totalWords: Int
    var totalRecordedSeconds: TimeInterval
    var lastCaptureAt: Date?

    static let empty = UsageStats(
        totalDictations: 0,
        totalRecordings: 0,
        totalCharacters: 0,
        totalWords: 0,
        totalRecordedSeconds: 0,
        lastCaptureAt: nil
    )

    init(
        totalDictations: Int,
        totalRecordings: Int,
        totalCharacters: Int,
        totalWords: Int,
        totalRecordedSeconds: TimeInterval,
        lastCaptureAt: Date?
    ) {
        self.totalDictations = totalDictations
        self.totalRecordings = totalRecordings
        self.totalCharacters = totalCharacters
        self.totalWords = totalWords
        self.totalRecordedSeconds = totalRecordedSeconds
        self.lastCaptureAt = lastCaptureAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalDictations = try container.decodeIfPresent(Int.self, forKey: .totalDictations) ?? 0
        totalRecordings = try container.decodeIfPresent(Int.self, forKey: .totalRecordings) ?? 0
        totalCharacters = try container.decodeIfPresent(Int.self, forKey: .totalCharacters) ?? 0
        totalWords = try container.decodeIfPresent(Int.self, forKey: .totalWords) ?? 0
        totalRecordedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .totalRecordedSeconds) ?? 0
        let latest = try container.decodeIfPresent(Date.self, forKey: .lastCaptureAt)
        let legacy = try container.decodeIfPresent(Date.self, forKey: .legacyLastDictationAt)
        lastCaptureAt = latest ?? legacy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalDictations, forKey: .totalDictations)
        try container.encode(totalRecordings, forKey: .totalRecordings)
        try container.encode(totalCharacters, forKey: .totalCharacters)
        try container.encode(totalWords, forKey: .totalWords)
        try container.encode(totalRecordedSeconds, forKey: .totalRecordedSeconds)
        try container.encodeIfPresent(lastCaptureAt, forKey: .lastCaptureAt)
    }

    private enum CodingKeys: String, CodingKey {
        case totalDictations
        case totalRecordings
        case totalCharacters
        case totalWords
        case totalRecordedSeconds
        case lastCaptureAt
        case legacyLastDictationAt = "lastDictationAt"
    }
}

private struct LegacyHistoryEntry: Codable {
    let id: UUID
    let createdAt: Date
    let text: String
    let provider: String
}

final class CaptureStore {
    private let supportDirectoryURL: URL
    private let capturesURL: URL
    private let legacyHistoryURL: URL
    private let statsURL: URL

    init(baseDirectory: URL) {
        supportDirectoryURL = baseDirectory
        capturesURL = baseDirectory.appendingPathComponent("captures.json")
        legacyHistoryURL = baseDirectory.appendingPathComponent("history.json")
        statsURL = baseDirectory.appendingPathComponent("stats.json")
    }

    func loadCaptures() -> [CaptureRecord] {
        if let data = try? Data(contentsOf: capturesURL),
           let items = try? JSONDecoder().decode([CaptureRecord].self, from: data) {
            return items
        }

        if let data = try? Data(contentsOf: legacyHistoryURL),
           let legacy = try? JSONDecoder().decode([LegacyHistoryEntry].self, from: data) {
            return legacy.map {
                CaptureRecord(
                    id: $0.id,
                    kind: .dictationSnippet,
                    startedAt: $0.createdAt,
                    endedAt: $0.createdAt,
                    durationSeconds: 0,
                    provider: $0.provider,
                    transcriptionModel: "",
                    cleanupModel: nil,
                    rawTranscript: $0.text,
                    finalText: $0.text,
                    summary: nil,
                    title: Self.makeTitle(for: .dictationSnippet, from: $0.text),
                    status: .completed
                )
            }
        }

        return []
    }

    func loadStats() -> UsageStats {
        guard let data = try? Data(contentsOf: statsURL),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data) else {
            return .empty
        }
        return stats
    }

    func append(
        kind: CaptureKind,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        provider: String,
        transcriptionModel: String,
        cleanupModel: String?,
        rawTranscript: String,
        finalText: String,
        summary: String? = nil,
        status: CaptureStatus = .completed
    ) throws -> ([CaptureRecord], UsageStats) {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        var captures = loadCaptures()
        var stats = loadStats()

        let record = CaptureRecord(
            id: UUID(),
            kind: kind,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            provider: provider,
            transcriptionModel: transcriptionModel,
            cleanupModel: cleanupModel,
            rawTranscript: rawTranscript,
            finalText: finalText,
            summary: summary,
            title: Self.makeTitle(for: kind, from: finalText),
            status: status
        )

        captures.insert(record, at: 0)
        captures = Array(captures.prefix(150))
        stats = Self.rebuildStats(from: captures)

        try saveCaptures(captures)
        try saveStats(stats)
        return (captures, stats)
    }

    func updateSummary(for captureID: UUID, summary: String) throws -> ([CaptureRecord], UsageStats)? {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        var captures = loadCaptures()
        guard let index = captures.firstIndex(where: { $0.id == captureID }) else {
            return nil
        }

        captures[index].summary = summary
        let stats = Self.rebuildStats(from: captures)
        try saveCaptures(captures)
        try saveStats(stats)
        return (captures, stats)
    }

    func clearCaptures() throws {
        try FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        try saveCaptures([])
        try saveStats(.empty)
    }

    private func saveCaptures(_ captures: [CaptureRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(captures)
        if data.last != 0x0A {
            data.append(0x0A)
        }
        try data.write(to: capturesURL, options: .atomic)
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

    private static func rebuildStats(from captures: [CaptureRecord]) -> UsageStats {
        var stats = UsageStats.empty
        stats.totalDictations = captures.filter { $0.kind == .dictationSnippet && $0.status == .completed }.count
        stats.totalRecordings = captures.filter { $0.kind == .recordingSession && $0.status == .completed }.count
        stats.totalCharacters = captures.reduce(0) { $0 + $1.characters }
        stats.totalWords = captures.reduce(0) { $0 + $1.words }
        stats.totalRecordedSeconds = captures
            .filter { $0.kind == .recordingSession && $0.status == .completed }
            .reduce(0) { $0 + $1.durationSeconds }
        stats.lastCaptureAt = captures.first?.endedAt
        return stats
    }

    private static func makeTitle(for kind: CaptureKind, from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return kind == .recordingSession ? "Untitled recording" : "Untitled dictation"
        }

        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let compact = firstLine.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if compact.count <= 52 {
            return compact
        }
        let index = compact.index(compact.startIndex, offsetBy: 52)
        return String(compact[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
