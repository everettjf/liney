//
//  AppSettingsDirectoryTreeTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AppSettingsDirectoryTreeTests: XCTestCase {
    func testDefaultsToDisabled() {
        XCTAssertFalse(AppSettings().directoryTreeEnabled)
    }

    func testRoundTrips() throws {
        var settings = AppSettings()
        settings.directoryTreeEnabled = true
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.directoryTreeEnabled)
    }

    func testLegacySettingsWithoutKeyDefaultToDisabled() throws {
        // Settings persisted before this flag existed default to off.
        let json = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(decoded.directoryTreeEnabled)
    }
}
