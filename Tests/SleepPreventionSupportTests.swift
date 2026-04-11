//
//  SleepPreventionSupportTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

@MainActor
final class SleepPreventionSupportTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        LocalizationManager.shared.updateSelectedLanguage(.english)
    }

    override func tearDown() async throws {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        try await super.tearDown()
    }
    
    func testSleepPreventionDurationsMatchExpectedSeconds() {
        XCTAssertEqual(SleepPreventionDurationOption.oneHour.duration, 3_600)
        XCTAssertEqual(SleepPreventionDurationOption.twelveHours.duration, 43_200)
        XCTAssertEqual(SleepPreventionDurationOption.threeDays.duration, 259_200)
        XCTAssertNil(SleepPreventionDurationOption.forever.duration)
    }

    func testDurationFormattingUsesLargestUnits() {
        let duration: TimeInterval = 95_400

        XCTAssertEqual(SleepPreventionFormat.duration(duration), "1d 2h")
    }

    func testForeverSessionUsesOnStatus() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = SleepPreventionSession(option: .forever, startedAt: now, expiresAt: nil)

        let description = await session.remainingDescription(relativeTo: now)
        XCTAssertEqual(description, "On")
    }
}
