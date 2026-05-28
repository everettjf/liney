//
//  DirectoryTreeLoaderTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class DirectoryTreeLoaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("liney-tree-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ name: String) throws {
        try Data().write(to: root.appendingPathComponent(name))
    }

    private func makeDir(_ name: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }

    func testDirectoriesSortBeforeFilesThenAlphabetical() throws {
        try makeFile("zebra.txt")
        try makeFile("apple.md")
        try makeDir("src")
        try makeDir("Assets")

        let entries = DirectoryTreeLoader.entries(at: root)
        let names = entries.map(\.name)
        XCTAssertEqual(names, ["Assets", "src", "apple.md", "zebra.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertTrue(entries[1].isDirectory)
        XCTAssertFalse(entries[2].isDirectory)
    }

    func testHiddenFilesFilteredByDefault() throws {
        try makeFile(".env")
        try makeFile("visible.md")

        let withoutHidden = DirectoryTreeLoader.entries(at: root)
        XCTAssertEqual(withoutHidden.map(\.name), ["visible.md"])

        let withHidden = DirectoryTreeLoader.entries(at: root, includesHidden: true)
        XCTAssertTrue(withHidden.contains { $0.name == ".env" })
    }

    func testPreviewableFlag() throws {
        try makeFile("doc.md")
        try makeFile("page.html")
        try makeFile("image.png")

        let entries = DirectoryTreeLoader.entries(at: root)
        let previewable = Set(entries.filter(\.isPreviewable).map(\.name))
        XCTAssertEqual(previewable, ["doc.md", "page.html"])
    }

    func testSymlinkAndTargetKeepDistinctIdentities() throws {
        try makeFile("AGENTS.md")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("CLAUDE.md"),
            withDestinationURL: root.appendingPathComponent("AGENTS.md")
        )

        let entries = DirectoryTreeLoader.entries(at: root)
        XCTAssertEqual(Set(entries.map(\.name)), ["AGENTS.md", "CLAUDE.md"])
        // Each entry's `id` (its url.path) must be unique, otherwise SwiftUI's
        // ForEach renders one row blank.
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }

    func testEntriesForMissingDirectoryIsEmpty() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertTrue(DirectoryTreeLoader.entries(at: missing).isEmpty)
    }

    func testIsReadableDirectory() throws {
        try makeFile("file.txt")
        XCTAssertTrue(DirectoryTreeLoader.isReadableDirectory(root.path))
        XCTAssertFalse(DirectoryTreeLoader.isReadableDirectory(root.appendingPathComponent("file.txt").path))
        XCTAssertFalse(DirectoryTreeLoader.isReadableDirectory(root.appendingPathComponent("nope").path))
    }
}
