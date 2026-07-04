//
//  LineyGhosttyConfigTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class LineyGhosttyConfigTests: XCTestCase {
    func testManagedConfigContentsIncludeFontOverrides() {
        let contents = LineyGhosttyConfigManager.managedConfigContents(
            settings: AppSettings(
                terminalFontFamily: "JetBrains Mono",
                terminalFontSize: 14.2
            )
        )

        XCTAssertTrue(contents.contains("font-family = \"JetBrains Mono\""))
        XCTAssertTrue(contents.contains("font-size = 14"))
    }

    func testManagedConfigContentsOnlyContainHeaderWithoutOverrides() {
        let contents = LineyGhosttyConfigManager.managedConfigContents(settings: AppSettings())

        XCTAssertEqual(
            contents,
            "# Managed by Liney. Manual edits will be overwritten.\n"
        )
    }

    func testManagedConfigEmitsScrollbackLimitInBytes() {
        let bytes = 32 * 1024 * 1024
        let contents = LineyGhosttyConfigManager.managedConfigContents(
            settings: AppSettings(terminalScrollbackBytes: bytes)
        )

        // Ghostty's scrollback-limit is a byte budget; we must emit the raw
        // byte count, not a line count.
        XCTAssertTrue(contents.contains("scrollback-limit = \(bytes)"))
    }

    func testManagedConfigOmitsScrollbackLimitWhenUnset() {
        let contents = LineyGhosttyConfigManager.managedConfigContents(settings: AppSettings())

        XCTAssertFalse(contents.contains("scrollback-limit"))
    }

    // MARK: - Scrollback migration

    func testDecodeMigratesLegacyLineCountToBytes() throws {
        // A settings blob from before the byte-based key existed: the number was
        // a line count that Ghostty mistakenly read as bytes.
        let json = Data(#"{"terminalScrollbackLines": 90000}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(
            settings.terminalScrollbackBytes,
            TerminalScrollback.bytes(forLegacyLines: 90000)
        )
        // 90,000 lines * ~1,900 B/line ≈ 163 MB, so the migration cap applies.
        XCTAssertEqual(settings.terminalScrollbackBytes, TerminalScrollback.migrationMaxBytes)
        // Sanity: the migrated budget is far above the 4 MB floor (the old value
        // was effectively 88 KB, a no-op).
        XCTAssertGreaterThanOrEqual(settings.terminalScrollbackBytes ?? 0, TerminalScrollback.minBytes)
    }

    func testLegacyMigrationIsCappedAtMigrationMax() {
        // Even an absurd legacy line count must not balloon per-terminal memory.
        XCTAssertEqual(
            TerminalScrollback.bytes(forLegacyLines: 10_000_000),
            TerminalScrollback.migrationMaxBytes
        )
    }

    func testDecodeClampsLegacyLineCountIntoRange() throws {
        // A tiny legacy value would convert below the floor; it must be clamped up.
        let json = Data(#"{"terminalScrollbackLines": 1000}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.terminalScrollbackBytes, TerminalScrollback.minBytes)
    }

    func testDecodePrefersByteKeyOverLegacyLineKey() throws {
        let bytes = 64 * 1024 * 1024
        let json = Data(#"{"terminalScrollbackBytes": \#(bytes), "terminalScrollbackLines": 5000}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.terminalScrollbackBytes, bytes)
    }

    func testDecodeLeavesScrollbackNilWhenAbsent() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertNil(settings.terminalScrollbackBytes)
    }

    func testByteBudgetRoundTripsThroughEncoding() throws {
        let original = AppSettings(terminalScrollbackBytes: 128 * 1024 * 1024)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.terminalScrollbackBytes, original.terminalScrollbackBytes)
    }
}
