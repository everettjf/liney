//
//  PresentationStateTests.swift
//  LineyTests
//

import Combine
import XCTest
@testable import Liney

@MainActor
final class PresentationStateTests: XCTestCase {
    func testCommandPaletteStatePublishesOnlyItsOwnChanges() {
        let store = WorkspaceStore(persistsWorkspaceState: false)
        var storeChangeCount = 0
        let cancellable = store.objectWillChange.sink { storeChangeCount += 1 }

        store.commandPalettePresentation.isPresented = true
        store.commandPalettePresentation.query = "worktree"
        store.commandPalettePresentation.selectedItemID = "command:new-tab"

        XCTAssertEqual(storeChangeCount, 0)
        XCTAssertTrue(store.isCommandPalettePresented)
        XCTAssertEqual(store.commandPaletteQuery, "worktree")
        XCTAssertEqual(store.selectedCommandPaletteItemID, "command:new-tab")
        withExtendedLifetime(cancellable) {}
    }

    func testStatusMessageStateDoesNotPublishThroughWorkspaceStore() {
        let store = WorkspaceStore(persistsWorkspaceState: false)
        var storeChangeCount = 0
        let cancellable = store.objectWillChange.sink { storeChangeCount += 1 }

        store.statusMessage = WorkspaceStatusMessage(text: "Saved", tone: .success)
        XCTAssertEqual(store.statusMessage?.text, "Saved")
        store.statusMessage = nil

        XCTAssertEqual(storeChangeCount, 0)
        XCTAssertNil(store.statusMessage)
        withExtendedLifetime(cancellable) {}
    }
}
