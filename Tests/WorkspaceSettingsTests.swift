//
//  WorkspaceSettingsTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class WorkspaceSettingsTests: XCTestCase {
    func testWorkspaceRecordDecodesDefaultSettingsFromLegacyPayload() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000111",
          "kind": "repository",
          "name": "Demo",
          "repositoryRoot": "/tmp/demo",
          "activeWorktreePath": "/tmp/demo",
          "worktreeStates": [
            {
              "worktreePath": "/tmp/demo",
              "layout": null,
              "panes": [],
              "focusedPaneID": null,
              "zoomedPaneID": null
            }
          ],
          "isSidebarExpanded": false,
          "worktrees": []
        }
        """

        let record = try JSONDecoder().decode(WorkspaceRecord.self, from: Data(json.utf8))

        XCTAssertFalse(record.settings.isPinned)
        XCTAssertFalse(record.settings.isArchived)
        XCTAssertEqual(record.settings.agentPresets.first?.name, "Codex")
        XCTAssertTrue(record.settings.remoteTargets.isEmpty)
        XCTAssertTrue(record.settings.workflows.isEmpty)
        XCTAssertTrue(record.activityLog.isEmpty)
    }

    func testWorkspaceRecordRoundTripPreservesSettings() throws {
        let record = WorkspaceRecord(
            id: UUID(),
            kind: .repository,
            name: "Demo",
            repositoryRoot: "/tmp/demo",
            activeWorktreePath: "/tmp/demo",
            worktreeStates: [WorktreeSessionStateRecord.makeDefault(for: "/tmp/demo")],
            isSidebarExpanded: true,
            worktrees: [],
            settings: WorkspaceSettings(
                isPinned: true,
                isArchived: true,
                workspaceIcon: SidebarItemIcon(
                    symbolName: "shippingbox.fill",
                    palette: .orange,
                    fillStyle: .gradient
                ),
                worktreeIconOverrides: [
                    "/tmp/demo": SidebarItemIcon(
                        symbolName: "bolt.fill",
                        palette: .mint,
                        fillStyle: .solid
                    )
                ],
                runScript: "make test",
                setupScript: "mise install",
                agentPresets: [
                    AgentPreset(
                        name: "Review",
                        launchPath: "/usr/bin/env",
                        arguments: ["codex", "review"],
                        environment: ["MODE": "review"],
                        workingDirectory: "/tmp/demo"
                    )
                ],
                preferredAgentPresetID: nil,
                remoteTargets: [
                    RemoteWorkspaceTarget(
                        name: "Prod Box",
                        ssh: SSHSessionConfiguration(
                            host: "prod.example.com",
                            user: "deploy",
                            port: 2222,
                            identityFilePath: "~/.ssh/prod",
                            remoteWorkingDirectory: "/srv/app",
                            remoteCommand: nil
                        ),
                        agentPresetID: nil
                    )
                ],
                workflows: [
                    WorkspaceWorkflow(
                        name: "Ship",
                        localSessionMode: .splitRight,
                        runSetupScript: true,
                        runWorkspaceScript: true,
                        agentPresetID: nil,
                        agentMode: .splitDown
                    )
                ],
                preferredWorkflowID: nil
            ),
            activityLog: [
                WorkspaceActivityEntry(
                    timestamp: 1_710_000_000,
                    kind: .workflow,
                    title: "Ran workflow",
                    detail: "Ship",
                    worktreePath: "/tmp/demo",
                    replayAction: .runWorkflow(UUID(uuidString: "00000000-0000-0000-0000-000000000222")!)
                )
            ]
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(WorkspaceRecord.self, from: data)

        XCTAssertTrue(decoded.settings.isPinned)
        XCTAssertTrue(decoded.settings.isArchived)
        XCTAssertEqual(decoded.settings.workspaceIcon?.symbolName, "shippingbox.fill")
        XCTAssertEqual(decoded.settings.workspaceIcon?.palette, .orange)
        XCTAssertEqual(decoded.settings.workspaceIcon?.fillStyle, .gradient)
        XCTAssertEqual(decoded.settings.worktreeIconOverrides["/tmp/demo"]?.symbolName, "bolt.fill")
        XCTAssertEqual(decoded.settings.worktreeIconOverrides["/tmp/demo"]?.palette, .mint)
        XCTAssertEqual(decoded.settings.worktreeIconOverrides["/tmp/demo"]?.fillStyle, .solid)
        XCTAssertEqual(decoded.settings.runScript, "make test")
        XCTAssertEqual(decoded.settings.setupScript, "mise install")
        XCTAssertEqual(decoded.settings.agentPresets.first?.arguments, ["codex", "review"])
        XCTAssertEqual(decoded.settings.agentPresets.first?.environment["MODE"], "review")
        XCTAssertEqual(decoded.settings.remoteTargets.first?.name, "Prod Box")
        XCTAssertEqual(decoded.settings.remoteTargets.first?.ssh.host, "prod.example.com")
        XCTAssertEqual(decoded.settings.remoteTargets.first?.ssh.remoteWorkingDirectory, "/srv/app")
        XCTAssertEqual(decoded.settings.workflows.first?.name, "Ship")
        XCTAssertEqual(decoded.settings.workflows.first?.localSessionMode, .splitRight)
        XCTAssertEqual(decoded.settings.workflows.first?.agentMode, .splitDown)
        XCTAssertEqual(decoded.activityLog.first?.kind, .workflow)
        XCTAssertEqual(decoded.activityLog.first?.title, "Ran workflow")
        XCTAssertEqual(decoded.activityLog.first?.replayAction?.kind, .runWorkflow)
    }

    func testWorkspaceSettingsDecodeLegacyPayloadWithoutIconFields() throws {
        let data = Data(
            """
            {
              "isPinned": true,
              "isArchived": false,
              "runScript": "make lint",
              "setupScript": "mise install",
              "agentPresets": [],
              "remoteTargets": [],
              "workflows": []
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(WorkspaceSettings.self, from: data)

        XCTAssertTrue(settings.isPinned)
        XCTAssertNil(settings.workspaceIcon)
        XCTAssertTrue(settings.worktreeIconOverrides.isEmpty)
        XCTAssertEqual(settings.runScript, "make lint")
        XCTAssertEqual(settings.setupScript, "mise install")
    }

    func testCreateSSHSessionDraftCanPromoteConnectionIntoReusableRemoteTarget() {
        var draft = CreateSSHSessionDraft()
        draft.saveAsTarget = true
        draft.targetName = "Prod Box"
        draft.host = "prod.example.com"
        draft.user = "deploy"
        draft.port = "2222"
        draft.identityFilePath = "~/.ssh/prod"
        draft.remoteWorkingDirectory = "/srv/app"
        draft.remoteCommand = "tmux attach || tmux"

        let saved = draft.targetToSave

        XCTAssertEqual(saved?.name, "Prod Box")
        XCTAssertEqual(saved?.ssh.host, "prod.example.com")
        XCTAssertEqual(saved?.ssh.user, "deploy")
        XCTAssertEqual(saved?.ssh.port, 2222)
        XCTAssertEqual(saved?.ssh.remoteCommand, "tmux attach || tmux")
    }

    func testCreateSSHSessionDraftAppliesSavedRemoteTargetFields() {
        let target = RemoteWorkspaceTarget(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            name: "GPU Box",
            ssh: SSHSessionConfiguration(
                host: "gpu.example.com",
                user: "ml",
                port: 2202,
                identityFilePath: "~/.ssh/gpu",
                remoteWorkingDirectory: "/srv/train",
                remoteCommand: "source ~/.zshrc"
            ),
            agentPresetID: nil
        )
        var draft = CreateSSHSessionDraft()

        draft.apply(remoteTarget: target)

        XCTAssertEqual(draft.selectedTargetID, target.id)
        XCTAssertEqual(draft.targetName, "GPU Box")
        XCTAssertEqual(draft.host, "gpu.example.com")
        XCTAssertEqual(draft.user, "ml")
        XCTAssertEqual(draft.port, "2202")
        XCTAssertEqual(draft.identityFilePath, "~/.ssh/gpu")
        XCTAssertEqual(draft.remoteWorkingDirectory, "/srv/train")
        XCTAssertEqual(draft.remoteCommand, "source ~/.zshrc")
    }

    func testRandomRepositoryIconUsesKnownCatalogValues() {
        let icon = SidebarItemIcon.randomRepository()

        XCTAssertTrue(SidebarIconCatalog.repositorySymbolNames.contains(icon.symbolName))
        XCTAssertTrue(SidebarIconPalette.allCases.contains(icon.palette))
        XCTAssertTrue(SidebarIconFillStyle.allCases.contains(icon.fillStyle))
    }

    func testSidebarIconCatalogHasExpandedPools() {
        XCTAssertGreaterThanOrEqual(SidebarIconCatalog.symbols.count, 60)
        XCTAssertGreaterThanOrEqual(SidebarIconPalette.allCases.count, 40)
    }

    func testRandomRepositoryIconAvoidsRecentSymbolAndPaletteWhenPossible() {
        let existingIcons: [SidebarItemIcon] = [
            SidebarItemIcon(symbolName: "arrow.triangle.branch", palette: .blue, fillStyle: .gradient),
            SidebarItemIcon(symbolName: "folder.fill", palette: .mint, fillStyle: .solid),
            SidebarItemIcon(symbolName: "tray.full.fill", palette: .orange, fillStyle: .gradient)
        ]

        let icon = SidebarItemIcon.randomRepository(avoiding: existingIcons)

        XCTAssertFalse(["arrow.triangle.branch", "folder.fill", "tray.full.fill"].contains(icon.symbolName))
        XCTAssertFalse([SidebarIconPalette.blue, .mint, .orange].contains(icon.palette))
    }

    func testSeededRandomRepositoryIconIsStableForSameRepositoryName() {
        let first = SidebarItemIcon.randomRepository(preferredSeed: "Liney", avoiding: [])
        let second = SidebarItemIcon.randomRepository(preferredSeed: "Liney", avoiding: [])

        XCTAssertEqual(first, second)
    }

    func testSeededRandomRepositoryIconFallsBackWhenPreferredChoiceAlreadyUsed() {
        let preferred = SidebarItemIcon.randomRepository(preferredSeed: "Liney", avoiding: [])
        let avoided = SidebarItemIcon.randomRepository(preferredSeed: "Liney", avoiding: [preferred])

        XCTAssertNotEqual(preferred.symbolName, avoided.symbolName)
        XCTAssertNotEqual(preferred.palette, avoided.palette)
    }

    func testSeededRandomRepositoryIconBiasesBackendRepositoriesTowardServerSymbols() {
        let icon = SidebarItemIcon.randomRepository(preferredSeed: "payments-api", avoiding: [])

        XCTAssertTrue([
            "server.rack",
            "cpu.fill",
            "network",
            "antenna.radiowaves.left.and.right"
        ].contains(icon.symbolName))
    }

    func testSeededRandomRepositoryIconBiasesDocsRepositoriesTowardDocumentationSymbols() {
        let icon = SidebarItemIcon.randomRepository(preferredSeed: "product-docs", avoiding: [])

        XCTAssertTrue([
            "doc.text.fill",
            "doc.richtext.fill",
            "books.vertical.fill",
            "archivebox.fill"
        ].contains(icon.symbolName))
    }

    func testGeneratedWorktreeIconsAreStableForSameSeeds() {
        let seedSources = [
            "/tmp/openclaw": "openclaw|main|/tmp/openclaw",
            "/tmp/openclaw-feature": "openclaw|feature/sidebar-icon|/tmp/openclaw-feature"
        ]

        let first = SidebarItemIcon.generatedWorktreeIcons(seedSourcesByID: seedSources)
        let second = SidebarItemIcon.generatedWorktreeIcons(seedSourcesByID: seedSources)

        XCTAssertEqual(first, second)
    }

    func testGeneratedWorktreeIconsAvoidDuplicatesWithinWorkspaceWhenPossible() {
        let icons = SidebarItemIcon.generatedWorktreeIcons(
            seedSourcesByID: [
                "/tmp/openclaw": "openclaw|main|/tmp/openclaw",
                "/tmp/openclaw-feature-a": "openclaw|feature/a|/tmp/openclaw-feature-a",
                "/tmp/openclaw-feature-b": "openclaw|feature/b|/tmp/openclaw-feature-b"
            ]
        )

        XCTAssertEqual(Set(icons.values).count, icons.count)
    }

    func testGeneratedWorktreeIconsRespectOverrides() {
        let override = SidebarItemIcon(
            symbolName: "bolt.fill",
            palette: .orange,
            fillStyle: .solid
        )

        let icons = SidebarItemIcon.generatedWorktreeIcons(
            seedSourcesByID: [
                "/tmp/openclaw": "openclaw|main|/tmp/openclaw",
                "/tmp/openclaw-feature": "openclaw|feature/sidebar-icon|/tmp/openclaw-feature"
            ],
            overrides: [
                "/tmp/openclaw-feature": override
            ]
        )

        XCTAssertEqual(icons["/tmp/openclaw-feature"], override)
    }
}
