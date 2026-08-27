//
//  PresentationStateTests.swift
//  LineyTests
//

import XCTest
@testable import Liney

@MainActor
final class PresentationStateTests: XCTestCase {
    func testCommandPaletteStateIsSharedThroughWorkspaceStoreAccessors() {
        let store = WorkspaceStore(persistsWorkspaceState: false)

        store.commandPalettePresentation.isPresented = true
        store.commandPalettePresentation.query = "worktree"
        store.commandPalettePresentation.selectedItemID = "command:new-tab"

        XCTAssertTrue(store.isCommandPalettePresented)
        XCTAssertEqual(store.commandPaletteQuery, "worktree")
        XCTAssertEqual(store.selectedCommandPaletteItemID, "command:new-tab")
    }

    func testStatusMessageStateCanBeSetAndClearedThroughWorkspaceStore() {
        let store = WorkspaceStore(persistsWorkspaceState: false)

        store.statusMessage = WorkspaceStatusMessage(text: "Saved", tone: .success)
        XCTAssertEqual(store.statusMessage?.text, "Saved")
        store.statusMessage = nil

        XCTAssertNil(store.statusMessage)
    }
}
