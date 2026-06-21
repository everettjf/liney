//
//  UnifiedPatchTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class UnifiedPatchTests: XCTestCase {
    private let twoFilePatch = """
    diff --git a/a.txt b/a.txt
    index 1111111..2222222 100644
    --- a/a.txt
    +++ b/a.txt
    @@ -1,2 +1,2 @@
     line1
    -line2
    +line2 changed
    @@ -10,2 +10,3 @@
     line10
    +inserted
     line11
    diff --git a/b.txt b/b.txt
    new file mode 100644
    index 0000000..3333333
    --- /dev/null
    +++ b/b.txt
    @@ -0,0 +1,1 @@
    +brand new

    """

    func testParseSplitsFilesAndHunks() {
        let sections = UnifiedPatch.parse(twoFilePatch)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].path, "a.txt")
        XCTAssertEqual(sections[0].hunks.count, 2)
        XCTAssertEqual(sections[1].path, "b.txt")
        XCTAssertEqual(sections[1].hunks.count, 1)

        XCTAssertEqual(sections[0].hunks[0].addedCount, 1)
        XCTAssertEqual(sections[0].hunks[0].removedCount, 1)
        XCTAssertEqual(sections[0].hunks[1].addedCount, 1)
        XCTAssertEqual(sections[0].hunks[1].removedCount, 0)
    }

    func testReassembleAllRoundTripsContent() {
        let sections = UnifiedPatch.parse(twoFilePatch)
        let allIDs = Set(sections.flatMap { $0.hunks.map(\.id) })
        let rebuilt = UnifiedPatch.reassemble(selectedHunkIDs: allIDs, from: sections)

        XCTAssertTrue(rebuilt.contains("a/a.txt"))
        XCTAssertTrue(rebuilt.contains("a/b.txt"))
        XCTAssertTrue(rebuilt.contains("line2 changed"))
        XCTAssertTrue(rebuilt.contains("inserted"))
        XCTAssertTrue(rebuilt.contains("brand new"))
    }

    func testReassembleSelectsSingleHunk() {
        let sections = UnifiedPatch.parse(twoFilePatch)
        // Only the second hunk of a.txt.
        let secondHunkID = sections[0].hunks[1].id
        let rebuilt = UnifiedPatch.reassemble(selectedHunkIDs: [secondHunkID], from: sections)

        XCTAssertTrue(rebuilt.contains("a/a.txt"))
        XCTAssertTrue(rebuilt.contains("inserted"))
        XCTAssertFalse(rebuilt.contains("line2 changed"))
        XCTAssertFalse(rebuilt.contains("b.txt"))
    }

    func testReassembleEmptySelectionIsEmpty() {
        let sections = UnifiedPatch.parse(twoFilePatch)
        XCTAssertTrue(UnifiedPatch.reassemble(selectedHunkIDs: [], from: sections).isEmpty)
    }

    func testBinaryChangeBecomesWholeFileHunk() {
        let patch = """
        diff --git a/img.png b/img.png
        new file mode 100644
        index 0000000..abcdef1
        Binary files /dev/null and b/img.png differ
        """
        let sections = UnifiedPatch.parse(patch)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].hunks.count, 1)
        XCTAssertTrue(sections[0].hunks[0].isWholeFile)

        let rebuilt = UnifiedPatch.reassemble(selectedHunkIDs: [sections[0].hunks[0].id], from: sections)
        XCTAssertTrue(rebuilt.contains("Binary files"))
    }
}
