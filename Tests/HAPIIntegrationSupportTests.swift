//
//  HAPIIntegrationSupportTests.swift
//  LineyTests
//
//  Author: Codex
//

import XCTest
@testable import Liney

final class HAPIIntegrationSupportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LocalizationManager.shared.updateSelectedLanguage(.english)
    }

    override func tearDown() {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        super.tearDown()
    }

    func testParseExecutablePathReturnsFirstAbsolutePath() {
        let output = """

        /opt/homebrew/bin/hapi
        /usr/local/bin/hapi
        """

        XCTAssertEqual(HAPIIntegrationCatalog.parseExecutablePath(output), "/opt/homebrew/bin/hapi")
    }

    func testInstallationUsesLaunchAsPrimaryAction() {
        let installation = HAPIInstallationStatus(executablePath: "/opt/homebrew/bin/hapi")

        XCTAssertEqual(installation.primaryActionTitle, "HAPI Claude Code")
        XCTAssertEqual(installation.primaryActionHelpText, "Launch HAPI in the current worktree")
    }
}
