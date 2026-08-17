//
//  PersistenceRecoveryTests.swift
//  LineyTests
//

import XCTest
@testable import Liney

final class PersistenceRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("liney-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAppSettingsFallsBackToLastValidBackup() throws {
        let persistence = AppSettingsPersistence(stateDirectoryURL: directory)
        var first = AppSettings()
        first.uiScale = 1.25
        persistence.save(first)
        persistence.flushPendingSync()

        var second = first
        second.uiScale = 1.5
        persistence.save(second)
        persistence.flushPendingSync()

        try Data("not-json".utf8).write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        let result = persistence.loadWithRecovery()

        XCTAssertEqual(result.source, .backup)
        XCTAssertEqual(result.value.uiScale, second.uiScale)
    }

    func testWorkspaceStateFallsBackToLastValidBackup() throws {
        let persistence = WorkspaceStatePersistence(stateDirectoryURL: directory)
        let firstID = UUID()
        let first = PersistedWorkspaceState(selectedWorkspaceID: firstID, workspaces: [])
        persistence.save(first)
        persistence.flushPendingSync()

        let second = PersistedWorkspaceState(selectedWorkspaceID: UUID(), workspaces: [])
        persistence.save(second)
        persistence.flushPendingSync()

        try Data("{".utf8).write(to: directory.appendingPathComponent("workspace-state.json"), options: .atomic)
        let result = persistence.loadWithRecovery()

        XCTAssertEqual(result.source, .backup)
        XCTAssertEqual(result.value.selectedWorkspaceID, second.selectedWorkspaceID)
    }

    func testUnrecoverablePrimaryIsQuarantinedInsteadOfOverwritten() throws {
        let primaryURL = directory.appendingPathComponent("settings.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: primaryURL)

        let result = AppSettingsPersistence(stateDirectoryURL: directory).loadWithRecovery()

        guard case .unrecoverable(let quarantinedURL) = result.source else {
            return XCTFail("Expected unrecoverable source")
        }
        let archiveURL = try XCTUnwrap(quarantinedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertEqual(try Data(contentsOf: archiveURL), corruptData)
    }

    func testMissingStateReturnsDefaultsWithoutCreatingAFile() {
        let primaryURL = directory.appendingPathComponent("workspace-state.json")
        let result = WorkspaceStatePersistence(stateDirectoryURL: directory).loadWithRecovery()

        XCTAssertEqual(result.source, .missing)
        XCTAssertTrue(result.value.workspaces.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
    }
}
