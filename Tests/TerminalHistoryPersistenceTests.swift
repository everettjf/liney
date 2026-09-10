import XCTest
@testable import Liney

final class TerminalHistoryPersistenceTests: XCTestCase {
    func testHistoryIsOptInAndRoundTrips() throws {
        XCTAssertFalse(AppSettings().restoreTerminalHistory)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).restoreTerminalHistory)
        let settings = AppSettings(restoreTerminalHistory: true)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).restoreTerminalHistory)
    }

    func testLatestSnapshotReplacesPreviousAndRemainsPaneSpecific() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = TerminalHistoryPersistence(directory: root)
        let first = UUID(), second = UUID()
        persistence.save("old", for: first)
        persistence.save("other pane", for: second)
        persistence.save("latest", for: first)
        persistence.flush()
        XCTAssertEqual(persistence.load(first), "latest")
        XCTAssertEqual(persistence.load(second), "other pane")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(first.uuidString).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        persistence.remove([first])
        persistence.flush()
        XCTAssertNil(persistence.load(first))
        XCTAssertEqual(persistence.load(second), "other pane")
        persistence.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testGlobalBudgetEvictsOldestSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = TerminalHistoryPersistence(directory: root, byteBudget: 6)
        let older = UUID(), newer = UUID()
        persistence.save("old!", for: older)
        persistence.flush()
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: root.appendingPathComponent(older.uuidString).path)
        persistence.save("new!", for: newer)
        persistence.flush()
        XCTAssertNil(persistence.load(older))
        XCTAssertEqual(persistence.load(newer), "new!")
    }

    func testClearWaitsForPendingWrites() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = TerminalHistoryPersistence(directory: root)
        for _ in 0..<10 { persistence.save("pending", for: UUID()) }
        persistence.clear()
        persistence.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testTruncationKeepsNewestCompleteUTF8Characters() {
        XCTAssertEqual(TerminalHistoryPersistence.boundedText("old你好", limit: 5), "好")
        XCTAssertEqual(TerminalHistoryPersistence.boundedText("old你好", limit: 6), "你好")
        XCTAssertEqual(TerminalHistoryPersistence.boundedText("hello", limit: 0), "")
    }

    func testCorruptOrOversizedSnapshotIsIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let url = root.appendingPathComponent(id.uuidString)
        let persistence = TerminalHistoryPersistence(directory: root)
        try Data([0xff, 0xfe]).write(to: url)
        XCTAssertNil(persistence.load(id))
        try Data(repeating: 65, count: TerminalHistoryPersistence.paneLimit + 1).write(to: url)
        XCTAssertNil(persistence.load(id))
    }
}
