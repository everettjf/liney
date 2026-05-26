//
//  PathFormattingTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class PathFormattingTests: XCTestCase {
    func testShellQuotedEscapesSingleQuotes() {
        XCTAssertEqual("/tmp/it's-liney".shellQuoted, "'/tmp/it'\\''s-liney'")
    }

    func testAbbreviatedPathUsesTildeInsideHomeDirectory() {
        let home = NSHomeDirectory()
        XCTAssertEqual("\(home)/src/liney".abbreviatedPath, "~/src/liney")
    }

    func testShellEscapedEscapesSpaces() {
        XCTAssertEqual(
            "/Users/eevv/Screen Studio Projects".shellEscaped,
            "/Users/eevv/Screen\\ Studio\\ Projects"
        )
    }

    func testShellEscapedEscapesShellMetacharacters() {
        XCTAssertEqual(
            "/tmp/a (b) & c$d'e\"f".shellEscaped,
            "/tmp/a\\ \\(b\\)\\ \\&\\ c\\$d\\'e\\\"f"
        )
    }

    func testShellEscapedLeavesPlainPathUnchanged() {
        XCTAssertEqual("/Users/eevv/src/liney".shellEscaped, "/Users/eevv/src/liney")
    }

    func testShellEscapedKeepsNonASCIIUnescaped() {
        XCTAssertEqual("/Users/eevv/文档".shellEscaped, "/Users/eevv/文档")
    }

    func testShellEscapedEmptyStringIsQuotedEmpty() {
        XCTAssertEqual("".shellEscaped, "''")
    }
}
