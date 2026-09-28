import XCTest
@testable import Liney

@MainActor
final class WorkbenchTests: XCTestCase {
    private func makeStore() -> WorkspaceStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liney-workbench-test-\(UUID().uuidString)")
        return WorkspaceStore(persistsWorkspaceState: false, persistenceCoordinator: WorkspacePersistenceCoordinator(
            workspacePersistence: WorkspaceStatePersistence(stateDirectoryURL: directory),
            settingsPersistence: AppSettingsPersistence(stateDirectoryURL: directory)),
            terminalHistoryCoordinator: TerminalHistoryCoordinator(persistence: TerminalHistoryPersistence(directory: directory.appendingPathComponent("history"))))
    }

    func testLaunchPreservesTabsSplitSelectionAndLegacyCanvasLayout() throws {
        let paneA = PaneSnapshot.makeDefault(cwd: "/tmp")
        let paneB = PaneSnapshot.makeDefault(cwd: "/private/tmp")
        let split = SessionLayoutNode.split(PaneSplitNode(axis: .vertical, first: .pane(PaneLeaf(paneID: paneA.id)), second: .pane(PaneLeaf(paneID: paneB.id))))
        let tabA = WorkspaceTabStateRecord(title: "Build", layout: split, panes: [paneA, paneB], focusedPaneID: paneB.id)
        let tabB = WorkspaceTabStateRecord.makeDefault(for: "/tmp")
        let record = WorkspaceRecord(id: UUID(), kind: .localTerminal, name: "Keep me", repositoryRoot: "/tmp", activeWorktreePath: "/tmp",
            worktreeStates: [WorktreeSessionStateRecord(worktreePath: "/tmp", layout: split, panes: [paneA, paneB], focusedPaneID: paneB.id,
                tabs: [tabA, tabB], selectedTabID: tabA.id)], isSidebarExpanded: false, settings: WorkspaceSettings(isStandaloneTerminal: true))
        let layout = GlobalCanvasCardLayoutRecord(workspaceID: record.id, worktreePath: "/tmp", tabID: tabA.id,
            centerX: 888, centerY: 444, width: 720, height: 500, isPinned: true)
        let input = PersistedWorkspaceState(selectedWorkspaceID: record.id, workspaces: [record], globalCanvasState: GlobalCanvasStateRecord(cardLayouts: [layout]))
        let decoded = try JSONDecoder().decode(PersistedWorkspaceState.self, from: JSONEncoder().encode(input))
        let normalized = makeStore().normalizeLaunchState(decoded)
        let restored = WorkspaceModel(record: try XCTUnwrap(normalized.workspaces.first))
        XCTAssertEqual(restored.activeWorktreeState.tabs.map(\.id), [tabA.id, tabB.id])
        XCTAssertEqual(restored.activeTabID, tabA.id)
        XCTAssertEqual(restored.layout, split)
        XCTAssertEqual(restored.sessionController.focusedPaneID, paneB.id)
        XCTAssertEqual(restored.sessionController.session(for: paneB.id)?.preferredWorkingDirectory, "/private/tmp")
        XCTAssertEqual(normalized.globalCanvasState.cardLayouts, [layout])
    }

    func testStandaloneCreationUsesHomeOrExplicitDirectory() {
        let store = makeStore()
        XCTAssertNil(store.selectedStandaloneTerminalDirectory)
        let home = store.createStandaloneTerminal()
        XCTAssertEqual(home.activeWorktreePath, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)
        XCTAssertTrue(home.isStandaloneTerminal)
        let temporary = store.createStandaloneTerminal(at: "/private/tmp")
        let expectedDirectory = URL(fileURLWithPath: "/private/tmp").standardizedFileURL.path
        XCTAssertEqual(temporary.activeWorktreePath, expectedDirectory)
        XCTAssertEqual(store.selectedStandaloneTerminalDirectory, expectedDirectory)
        XCTAssertTrue(temporary.isStandaloneTerminal)
        XCTAssertEqual(store.standaloneTerminals.count, 2)
        store.closeStandaloneTerminal(temporary)
        store.closeStandaloneTerminal(home)
        XCTAssertTrue(store.standaloneTerminals.isEmpty)
        XCTAssertNil(store.selectedStandaloneTerminalDirectory)
    }

    func testFreeformViewportKeepsFocusAndNearbyCardsButCullsDistantCards() {
        let viewport = CGSize(width: 800, height: 600)
        let card = CGSize(width: 400, height: 300)
        XCTAssertTrue(WorkbenchViewport.shouldMount(center: CGPoint(x: 400, y: 300), size: card, scale: 1, viewport: viewport, isSelected: false))
        XCTAssertTrue(WorkbenchViewport.shouldMount(center: CGPoint(x: 1000, y: 300), size: card, scale: 1, viewport: viewport, isSelected: false))
        XCTAssertFalse(WorkbenchViewport.shouldMount(center: CGPoint(x: 1600, y: 300), size: card, scale: 1, viewport: viewport, isSelected: false))
        XCTAssertTrue(WorkbenchViewport.shouldMount(center: CGPoint(x: 1600, y: 300), size: card, scale: 1, viewport: viewport, isSelected: true))
        XCTAssertTrue(WorkbenchViewport.shouldMount(center: CGPoint(x: 1600, y: 300), size: card, scale: 4, viewport: viewport, isSelected: false))
        XCTAssertTrue(WorkbenchViewport.shouldMount(center: CGPoint(x: 1600, y: 300), size: card, scale: 1, viewport: .zero, isSelected: false))
    }

    func testFailedCIAndDirtyWorktreeProduceOneAttentionRow() throws {
        var record = WorkspaceModel(localDirectoryPath: "/tmp").snapshot()
        record.kind = .repository
        let workspace = WorkspaceModel(record: record)
        workspace.changedFileCount = 12
        workspace.hasUncommittedChanges = true
        workspace.gitHubStatuses["/tmp"] = GitHubWorktreeStatus(checksSummary: GitHubPullRequestChecksSummary(
            passingCount: 0, failingCount: 1, pendingCount: 0, skippedCount: 0, failingChecks: []), refreshedAt: Date())
        let store = makeStore()
        store.workspaces = [workspace]
        let item = try XCTUnwrap(store.workbenchItems().first)
        let rows = WorkbenchAttention.make(items: [item, item])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.priority, 2)
        XCTAssertTrue(rows.first?.details.contains("12") == true)
    }

    func testNewDefaultShortcutPreservesExistingQuickCommandBinding() {
        let shortcut = LineyShortcutAction.newStandaloneTerminal.defaultShortcut
        let settings = AppSettings(quickCommandPresets: [QuickCommandPreset(id: "existing", title: "Existing", command: "pwd", categoryID: QuickCommandCategory.codex.id, shortcut: shortcut)])
        XCTAssertEqual(settings.quickCommandPresets.first?.shortcut, shortcut)
        XCTAssertNil(LineyKeyboardShortcuts.effectiveShortcut(for: .newStandaloneTerminal, in: settings))
        XCTAssertEqual(LineyKeyboardShortcuts.effectiveShortcut(for: .newStandaloneTerminal, in: AppSettings()), shortcut)
    }

    func testCleanWorktreeStillDisplaysFailedChecksAndStaleStatus() throws {
        let workspace = WorkspaceModel(localDirectoryPath: "/tmp")
        let store = makeStore()
        store.workspaces = [workspace]
        let item = try XCTUnwrap(store.workbenchItems().first)
        XCTAssertFalse(item.hasSecondarySummary)
        workspace.gitHubStatuses["/tmp"] = GitHubWorktreeStatus(checksSummary: GitHubPullRequestChecksSummary(
            passingCount: 0, failingCount: 1, pendingCount: 0, skippedCount: 0, failingChecks: []), refreshedAt: Date())
        XCTAssertEqual(item.changedFileCount, 0)
        XCTAssertEqual(item.failingCheckCount, 1)
        XCTAssertTrue(item.hasSecondarySummary)
        workspace.gitHubStatuses["/tmp"]?.checksSummary = nil
        workspace.gitHubStatuses["/tmp"]?.refreshError = "offline"
        XCTAssertTrue(item.hasStaleGitHubStatus)
        XCTAssertTrue(item.hasSecondarySummary)
    }
    override func tearDown() {
        AgentStatusStore.shared.clearAll()
        super.tearDown()
    }

    func testEnumerationDoesNotStartSavedTerminalsAndPinsAreShared() throws {
        let workspace = WorkspaceModel(localDirectoryPath: "/tmp", isStandaloneTerminal: true)
        let store = makeStore()
        store.workspaces = [workspace]
        let before = workspace.sessionController.sessions.values.map(\.lifecycle)
        let item = try XCTUnwrap(store.workbenchItems().first)
        XCTAssertFalse(item.isStarted)
        store.toggleWorkbenchPin(item.id)
        XCTAssertTrue(try XCTUnwrap(store.workbenchItems().first).isPinned)
        XCTAssertEqual(workspace.sessionController.sessions.values.map(\.lifecycle), before)
        let decoded = try JSONDecoder().decode(PersistedWorkspaceState.self, from: JSONEncoder().encode(store.currentStateSnapshot()))
        XCTAssertEqual(decoded.globalCanvasState.cardLayouts.first?.cardID, item.id)
        XCTAssertTrue(decoded.workspaces[0].settings.isStandaloneTerminal)
    }

    func testWaitingStateTargetsReportedPaneAndReadingDoesNotResolveIt() throws {
        let workspace = WorkspaceModel(localDirectoryPath: "/tmp", isStandaloneTerminal: true)
        let store = makeStore()
        store.workspaces = [workspace]
        let pane = try XCTUnwrap(workspace.paneOrder.first)
        AgentStatusStore.shared.update(pane: pane, state: .waiting, title: "Choose a migration")
        let item = try XCTUnwrap(store.workbenchItems().first)
        XCTAssertEqual(item.location.paneID, pane)
        XCTAssertTrue(item.isUnread)
        store.recordWorkbenchVisit(workspace, at: Date().addingTimeInterval(10))
        let read = try XCTUnwrap(store.workbenchItems().first)
        XCTAssertFalse(read.isUnread)
        XCTAssertTrue(read.needsAttention)
        XCTAssertEqual(WorkbenchAttention.make(items: [read]).count, 1)
    }

    func testDirtyStateAloneDoesNotCreateAttention() {
        var record = WorkspaceModel(localDirectoryPath: "/tmp").snapshot()
        record.kind = .repository
        let workspace = WorkspaceModel(record: record)
        workspace.hasUncommittedChanges = true
        workspace.changedFileCount = 12
        let store = makeStore()
        store.workspaces = [workspace]
        XCTAssertTrue(WorkbenchAttention.make(items: store.workbenchItems()).isEmpty)
    }

    func testGroupedAttentionOffersUnreadTabBeforeAlreadyReadWaitingTab() throws {
        var record = WorkspaceModel(localDirectoryPath: "/tmp", isStandaloneTerminal: true).snapshot()
        var state = try XCTUnwrap(record.worktreeStates.first)
        let secondTab = WorkspaceTabStateRecord.makeDefault(for: "/tmp")
        state.tabs.append(secondTab)
        record.worktreeStates = [state]
        let workspace = WorkspaceModel(record: record)
        let store = makeStore()
        store.workspaces = [workspace]
        for tab in state.tabs {
            AgentStatusStore.shared.update(pane: try XCTUnwrap(tab.panes.first?.id), state: .waiting, title: "Input needed")
        }
        let before = try XCTUnwrap(WorkbenchAttention.make(items: store.workbenchItems()).first)
        workspace.settings.workbenchVisits[before.item.id.id] = Date().addingTimeInterval(5)
        let groups = WorkbenchAttention.make(items: store.workbenchItems())
        XCTAssertEqual(groups.count, 1)
        let after = try XCTUnwrap(groups.first)
        XCTAssertNotEqual(after.item.id, before.item.id)
        XCTAssertTrue(after.isUnread)
        XCTAssertTrue(after.details.contains("2"))
        XCTAssertEqual(store.workbenchItems().filter(\.needsAttention).count, 2)
    }

    func testLastStandaloneTabClosesWithoutCreatingReplacementShell() throws {
        let workspace = WorkspaceModel(localDirectoryPath: "/tmp", isStandaloneTerminal: true)
        let store = makeStore()
        store.workspaces = [workspace]
        store.closeTab(in: workspace, tabID: try XCTUnwrap(workspace.activeTabID))
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertNil(store.selectedWorkspaceID)
    }

    func testLegacyLocalWorkspaceStaysInProjectList() {
        let legacy = WorkspaceModel(localDirectoryPath: "/tmp", name: "Terminal")
        let standalone = WorkspaceModel(localDirectoryPath: "/tmp", name: "Terminal", isStandaloneTerminal: true)
        let store = makeStore()
        store.workspaces = [legacy, standalone]
        XCTAssertEqual(store.sidebarWorkspaces.map(\.id), [legacy.id])
        XCTAssertEqual(store.standaloneTerminals.map(\.id), [standalone.id])
    }
}
