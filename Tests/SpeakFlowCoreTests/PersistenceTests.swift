import Foundation
import XCTest
@testable import SpeakFlowCore

final class PersistenceTests: XCTestCase {
    func testConfigStoreCreatesAndLoadsDefaultConfig() throws {
        let baseDirectory = try makeTempDirectory()
        let store = ConfigStore(baseDirectory: baseDirectory)

        let created = try store.ensureConfigExists()
        let loaded = try store.load()
        let data = try Data(contentsOf: store.configURL)

        XCTAssertTrue(created)
        XCTAssertEqual(loaded.providerName, AppConfig.default().providerName)
        XCTAssertEqual(data.last, 0x0A)
    }

    func testConfigStoreSaveRoundTripsCustomConfig() throws {
        let baseDirectory = try makeTempDirectory()
        let store = ConfigStore(baseDirectory: baseDirectory)
        var config = AppConfig.default()
        config.providerName = "Team Build"
        config.hotkeyBinding = HotkeyBinding.rightControl.rawValue

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded.providerName, "Team Build")
        XCTAssertEqual(loaded.resolvedHotkeyBinding(), .rightControl)
    }

    func testHistoryStoreAppendUpdatesHistoryAndStats() throws {
        let baseDirectory = try makeTempDirectory()
        let store = HistoryStore(baseDirectory: baseDirectory)

        let (history, stats) = try store.append(text: "Hello from SpeakFlow", provider: "Tests")

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.provider, "Tests")
        XCTAssertEqual(history.first?.words, 3)
        XCTAssertEqual(stats.totalDictations, 1)
        XCTAssertEqual(stats.totalWords, 3)
        XCTAssertEqual(stats.totalCharacters, "Hello from SpeakFlow".count)
        XCTAssertNotNil(stats.lastDictationAt)
    }

    func testHistoryStoreKeepsOnlyLatestHundredEntries() throws {
        let baseDirectory = try makeTempDirectory()
        let store = HistoryStore(baseDirectory: baseDirectory)

        for index in 0..<105 {
            _ = try store.append(text: "Entry \(index)", provider: "Tests")
        }

        let history = store.loadHistory()
        let stats = store.loadStats()

        XCTAssertEqual(history.count, 100)
        XCTAssertEqual(stats.totalDictations, 105)
        XCTAssertEqual(history.first?.text, "Entry 104")
        XCTAssertEqual(history.last?.text, "Entry 5")
    }

    func testClearHistoryRemovesEntriesButKeepsStatsFileReadable() throws {
        let baseDirectory = try makeTempDirectory()
        let store = HistoryStore(baseDirectory: baseDirectory)
        _ = try store.append(text: "Entry 1", provider: "Tests")

        try store.clearHistory()

        XCTAssertEqual(store.loadHistory(), [])
        XCTAssertEqual(store.loadStats().totalDictations, 1)
    }
}
