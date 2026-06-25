//
//  TerminalInlineImageFilterTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class TerminalInlineImageFilterTests: XCTestCase {
    private let helperPath = "/Applications/Liney.app/Contents/Resources/liney-osc-filter"

    func testWrapsCommandThroughHelperWithOriginalAsArguments() {
        let command = TerminalCommandDefinition(
            executablePath: "/bin/zsh",
            arguments: ["-l"],
            displayName: "zsh"
        )

        let wrapped = TerminalInlineImageFilter.wrapped(command: command, helperPath: helperPath)

        XCTAssertEqual(wrapped.executablePath, helperPath)
        XCTAssertEqual(wrapped.arguments, ["/bin/zsh", "-l"])
        // Display name is preserved so the UI/title is unaffected by wrapping.
        XCTAssertEqual(wrapped.displayName, "zsh")
    }

    func testWrappingPreservesAllOriginalArguments() {
        let command = TerminalCommandDefinition(
            executablePath: "/usr/bin/env",
            arguments: ["claude", "--continue", "--flag=value"],
            displayName: "Agent"
        )

        let wrapped = TerminalInlineImageFilter.wrapped(command: command, helperPath: helperPath)

        XCTAssertEqual(wrapped.arguments, ["/usr/bin/env", "claude", "--continue", "--flag=value"])
    }

    func testDoesNotDoubleWrapWhenExecutableIsAlreadyTheHelper() {
        let alreadyWrapped = TerminalCommandDefinition(
            executablePath: helperPath,
            arguments: ["/bin/zsh", "-l"],
            displayName: "zsh"
        )

        let result = TerminalInlineImageFilter.wrapped(command: alreadyWrapped, helperPath: helperPath)

        XCTAssertEqual(result, alreadyWrapped)
    }

    func testLeavesEmptyExecutableUntouched() {
        let empty = TerminalCommandDefinition(executablePath: "", arguments: [], displayName: "")

        let result = TerminalInlineImageFilter.wrapped(command: empty, helperPath: helperPath)

        XCTAssertEqual(result, empty)
    }
}
