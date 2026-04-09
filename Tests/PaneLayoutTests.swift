//
//  PaneLayoutTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class PaneLayoutTests: XCTestCase {
    func testSplitAndRemovePaneKeepsTreeValid() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        var root: SessionLayoutNode = .pane(PaneLeaf(paneID: first))
        XCTAssertTrue(root.split(paneID: first, axis: .vertical, newPaneID: second))
        XCTAssertTrue(root.split(paneID: second, axis: .horizontal, newPaneID: third))

        XCTAssertEqual(root.paneIDs, [first, second, third])

        _ = root.removePane(second)
        XCTAssertEqual(Set(root.paneIDs), Set([first, third]))
    }

    func testEqualizeSplitsRecursivelyResetsFractions() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        var root: SessionLayoutNode = .split(
            PaneSplitNode(
                axis: .vertical,
                fraction: 0.2,
                first: .pane(PaneLeaf(paneID: first)),
                second: .split(
                    PaneSplitNode(
                        axis: .horizontal,
                        fraction: 0.8,
                        first: .pane(PaneLeaf(paneID: second)),
                        second: .pane(PaneLeaf(paneID: third))
                    )
                )
            )
        )

        root.equalizeSplits()

        guard case .split(let outer) = root else {
            return XCTFail("Expected split root")
        }
        XCTAssertEqual(outer.fraction, 1.0 / 3.0, accuracy: 0.0001)

        guard case .split(let inner) = outer.second else {
            return XCTFail("Expected nested split")
        }
        XCTAssertEqual(inner.fraction, 0.5, accuracy: 0.0001)
    }

    func testDirectionalFocusUsesSplitAxes() {
        let left = UUID()
        let middle = UUID()
        let bottom = UUID()

        let layout: SessionLayoutNode = .split(
            PaneSplitNode(
                axis: .vertical,
                first: .pane(PaneLeaf(paneID: left)),
                second: .split(
                    PaneSplitNode(
                        axis: .horizontal,
                        first: .pane(PaneLeaf(paneID: middle)),
                        second: .pane(PaneLeaf(paneID: bottom))
                    )
                )
            )
        )

        XCTAssertEqual(layout.paneID(in: .left, from: middle), left)
        XCTAssertEqual(layout.paneID(in: .down, from: middle), bottom)
        XCTAssertEqual(layout.paneID(in: .up, from: bottom), middle)
        XCTAssertNil(layout.paneID(in: .right, from: bottom))
    }
}
