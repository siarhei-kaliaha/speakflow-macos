import AppKit
import Foundation
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

