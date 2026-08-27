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
        let state = CommandPalettePresentationState()
        var changeCount = 0
        let cancellable = state.objectWillChange.sink { changeCount += 1 }

        state.isPresented = true
        state.query = "worktree"
        state.selectedItemID = "command:new-tab"

        XCTAssertEqual(changeCount, 3)
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.query, "worktree")
        XCTAssertEqual(state.selectedItemID, "command:new-tab")
        withExtendedLifetime(cancellable) {}
    }

    func testStatusMessageStateCanClearAnExistingBanner() {
        let state = StatusMessagePresentationState()
        var changeCount = 0
        let cancellable = state.objectWillChange.sink { changeCount += 1 }

        state.message = WorkspaceStatusMessage(text: "Saved", tone: .success)
        state.message = nil

        XCTAssertEqual(changeCount, 2)
        XCTAssertNil(state.message)
        withExtendedLifetime(cancellable) {}
    }
}
