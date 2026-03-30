//
//  AppLanguageTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AppLanguageTests: XCTestCase {
    func testAppSettingsDefaultsToAutomaticLanguage() {
        let settings = AppSettings()

        XCTAssertEqual(settings.appLanguage, .automatic)
        XCTAssertEqual(settings.agentPresets.first?.name, "Claude Code")
        XCTAssertEqual(settings.preferredAgentPresetID, AgentPreset.claudeCode.id)
    }

    func testAppLanguageCodableRoundTrips() throws {
        let original = AppLanguage.simplifiedChinese

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppLanguage.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDisplayLabelsAreStableForSettingsPicker() {
        XCTAssertEqual(AppLanguage.automatic.displayName, "Automatic")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
    }
}
