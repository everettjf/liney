//
//  AgentPresetTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentPresetTests: XCTestCase {
    func testBuiltInPresetsIncludeCommonAgentCLIs() {
        let names = AgentPreset.builtInPresets.map(\.name)

        XCTAssertEqual(names, [
            "Claude Code",
            "Codex",
            "OpenCode",
            "Cursor Agent",
            "Gemini CLI",
        ])
    }

    func testBuiltInPresetsUseStableIdentifiers() {
        XCTAssertEqual(
            AgentPreset.builtInPresets.map(\.id),
            [
                AgentPreset.claudeCode.id,
                AgentPreset.codex.id,
                AgentPreset.openCode.id,
                AgentPreset.cursorAgent.id,
                AgentPreset.geminiCli.id,
            ]
        )
    }

    func testBuiltInSSHPresetsIncludeCommonRemoteCommands() {
        let names = SSHPreset.builtInPresets.map(\.name)

        XCTAssertEqual(names, [
            "Shell",
            "Lazygit",
            "Yazi",
            "Btop",
        ])
    }
}
