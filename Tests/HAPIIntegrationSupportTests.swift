//
//  HAPIIntegrationSupportTests.swift
//  LineyTests
//
//  Author: Codex
//

import XCTest
@testable import Liney

final class HAPIIntegrationSupportTests: XCTestCase {
    func testParseExecutablePathReturnsFirstAbsolutePath() {
        let output = """
        
        /opt/homebrew/bin/hapi
        /usr/local/bin/hapi
        """

        XCTAssertEqual(HAPIIntegrationCatalog.parseExecutablePath(output), "/opt/homebrew/bin/hapi")
    }

    func testParseAuthStatusDetectsConfiguredInstall() {
        let output = """
        Direct Connect Status

          HAPI_API_URL: http://localhost:3006
          CLI_API_TOKEN: set
          Token Source: settings file
        """

        let status = HAPIAuthStatus.parse(output)

        XCTAssertEqual(status.apiURL, "http://localhost:3006")
        XCTAssertTrue(status.hasToken)
        XCTAssertEqual(status.tokenSource, "settings file")
    }

    func testParseAuthStatusDetectsMissingToken() {
        let output = """
        Direct Connect Status

          HAPI_API_URL: http://localhost:3006
          CLI_API_TOKEN: missing
          Token Source: none
        """

        let status = HAPIAuthStatus.parse(output)

        XCTAssertEqual(status.apiURL, "http://localhost:3006")
        XCTAssertFalse(status.hasToken)
        XCTAssertEqual(status.tokenSource, "none")
    }

    func testPrimaryActionStartsHubBeforeAuthIsConfigured() {
        let installation = HAPIInstallationStatus(
            executablePath: "/opt/homebrew/bin/hapi",
            authStatus: HAPIAuthStatus(apiURL: "http://localhost:3006", hasToken: false, tokenSource: nil)
        )

        XCTAssertEqual(installation.primaryAction, .startHub)
        XCTAssertEqual(installation.primaryActionTitle, "Start HAPI Hub")
    }

    func testPrimaryActionLaunchesSessionWhenAuthIsConfigured() {
        let installation = HAPIInstallationStatus(
            executablePath: "/opt/homebrew/bin/hapi",
            authStatus: HAPIAuthStatus(apiURL: "http://localhost:3006", hasToken: true, tokenSource: "settings file")
        )

        XCTAssertEqual(installation.primaryAction, .launchSession)
        XCTAssertEqual(installation.primaryActionTitle, "Launch HAPI in Current Project")
    }
}
