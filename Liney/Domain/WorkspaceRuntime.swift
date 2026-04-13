//
//  WorkspaceRuntime.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import Foundation

@MainActor
final class WorkspaceModel: ObservableObject, Identifiable {
    let id: UUID
    let kind: WorkspaceKind
    let repositoryRoot: String

    @Published var name: String
    @Published var activeWorktreePath: String
    @Published var currentBranch: String
    @Published var head: String
    @Published var hasUncommittedChanges: Bool
    @Published var changedFileCount: Int
    @Published var aheadCount: Int
    @Published var behindCount: Int
    @Published var localBranches: [String]
    @Published var remoteBranches: [String]
    @Published var worktrees: [WorktreeModel]
    @Published var worktreeStatuses: [String: RepositoryStatusSnapshot]
    @Published var gitHubStatuses: [String: GitHubWorktreeStatus]
    @Published var activeTabID: UUID?
    @Published var layout: SessionLayoutNode?
    @Published var isSidebarExpanded: Bool
    @Published var settings: WorkspaceSettings
    @Published var activityLog: [WorkspaceActivityEntry]
    @Published var sessionController: WorkspaceSessionController
    @Published var zoomedPaneID: UUID?
    @Published var sshTarget: SSHSessionConfiguration?

    var isRemote: Bool { sshTarget != nil }

    private var worktreeStates: [String: WorktreeSessionStateRecord]
    private var worktreeControllers: [String: [UUID: WorkspaceSessionController]]

    init(record: WorkspaceRecord) {
        self.id = record.id
        self.kind = record.kind
        self.repositoryRoot = record.repositoryRoot
        self.sshTarget = record.sshTarget
        self.name = record.name
        self.activeWorktreePath = record.activeWorktreePath
        self.currentBranch = "-"
        self.head = "-"
        self.hasUncommittedChanges = false
        self.changedFileCount = 0
        self.aheadCount = 0
        self.behindCount = 0
        self.localBranches = []
        self.remoteBranches = []
        self.worktrees = record.worktrees
        self.worktreeStatuses = [:]
        self.gitHubStatuses = [:]
        self.activeTabID = nil
        self.zoomedPaneID = nil
        self.settings = record.settings
        self.activityLog = record.activityLog.sorted { $0.timestamp > $1.timestamp }
        self.worktreeStates = Dictionary(uniqueKeysWithValues: record.worktreeStates.map { ($0.worktreePath, $0) })
        let activeState = self.worktreeStates[record.activeWorktreePath] ?? WorktreeSessionStateRecord.makeDefault(for: record.activeWorktreePath)
        let activeTab = activeState.selectedTab ?? WorkspaceTabStateRecord.makeDefault(for: record.activeWorktreePath)
        self.activeTabID = activeState.selectedTabID ?? activeTab.id
        self.layout = activeTab.layout
        self.isSidebarExpanded = record.isSidebarExpanded
        let activeController = WorkspaceSessionController(workspaceID: record.id, paneSnapshots: activeTab.panes)
        activeController.focusedPaneID = activeTab.focusedPaneID
        self.worktreeControllers = [record.activeWorktreePath: [activeTab.id: activeController]]
        self.sessionController = activeController
        self.zoomedPaneID = activeTab.zoomedPaneID
        if record.kind == .localTerminal {
            currentBranch = "local"
            head = "shell"
            worktrees = [
                WorktreeModel(
                    path: record.activeWorktreePath,
                    branch: "local",
                    head: "shell",
                    isMainWorktree: true,
                    isLocked: false,
                    lockReason: nil
                )
            ]
        }
        bootstrapIfNeeded()
    }

    convenience init(snapshot: RepositorySnapshot) {
        let initialPane = PaneSnapshot.makeDefault(cwd: snapshot.rootPath)
        self.init(
            record: WorkspaceRecord(
                id: UUID(),
                kind: .repository,
                name: URL(fileURLWithPath: snapshot.rootPath).lastPathComponent,
                repositoryRoot: snapshot.rootPath,
                activeWorktreePath: snapshot.rootPath,
                worktreeStates: [
                    WorktreeSessionStateRecord(
                        worktreePath: snapshot.rootPath,
                        layout: .pane(PaneLeaf(paneID: initialPane.id)),
                        panes: [initialPane],
                        focusedPaneID: initialPane.id,
                        zoomedPaneID: nil
                    )
                ],
                isSidebarExpanded: false,
                settings: WorkspaceSettings(),
                activityLog: []
            )
        )
        apply(snapshot: snapshot)
    }

    convenience init(localDirectoryPath: String, name: String = "Terminal") {
        let normalizedPath = URL(fileURLWithPath: localDirectoryPath).standardizedFileURL.path
        self.init(
            record: WorkspaceRecord(
                id: UUID(),
                kind: .localTerminal,
                name: name,
                repositoryRoot: normalizedPath,
                activeWorktreePath: normalizedPath,
                worktreeStates: [
                    WorktreeSessionStateRecord.makeDefault(for: normalizedPath)
                ],
                isSidebarExpanded: false,
                settings: WorkspaceSettings(),
                activityLog: []
            )
        )
        currentBranch = "local"
        head = "shell"
        localBranches = []
        remoteBranches = []
        worktrees = [
            WorktreeModel(
                path: normalizedPath,
                branch: "local",
                head: "shell",
                isMainWorktree: true,
                isLocked: false,
                lockReason: nil
            )
        ]
    }

    var supportsRepositoryFeatures: Bool {
        kind == .repository || kind == .remoteServer
    }

    var activeWorktree: WorktreeModel? {
        worktrees.first(where: { $0.path == activeWorktreePath })
    }

    var activeSessionCount: Int {
        sessionController.activeSessionCount
    }

    var quitConfirmationSessionCount: Int {
        worktreeControllers.values.reduce(0) { partialResult, controllers in
            partialResult + controllers.values.reduce(0) { $0 + $1.quitConfirmationSessionCount }
        }
    }

    var isPinned: Bool {
        get { settings.isPinned }
        set { settings.isPinned = newValue }
    }

    var isArchived: Bool {
        get { settings.isArchived }
        set { settings.isArchived = newValue }
    }

    var workspaceIconOverride: SidebarItemIcon? {
        get { settings.workspaceIcon }
        set { settings.workspaceIcon = newValue }
    }

    var runScript: String {
        get { settings.runScript }
        set { settings.runScript = newValue }
    }

    var setupScript: String {
        get { settings.setupScript }
        set { settings.setupScript = newValue }
    }

    var agentPresets: [AgentPreset] {
        get { settings.agentPresets }
        set { settings.agentPresets = newValue }
    }

    var preferredAgentPresetID: UUID? {
        get { settings.preferredAgentPresetID }
        set { settings.preferredAgentPresetID = newValue }
    }

    var preferredAgentPreset: AgentPreset? {
        if let preferredAgentPresetID,
           let match = agentPresets.first(where: { $0.id == preferredAgentPresetID }) {
            return match
        }
        return agentPresets.first
    }

    var remoteTargets: [RemoteWorkspaceTarget] {
        get { settings.remoteTargets }
        set { settings.remoteTargets = newValue }
    }

    var workflows: [WorkspaceWorkflow] {
        get { settings.workflows }
        set { settings.workflows = newValue }
    }

    var preferredWorkflowID: UUID? {
        get { settings.preferredWorkflowID }
        set { settings.preferredWorkflowID = newValue }
    }

    var preferredWorkflow: WorkspaceWorkflow? {
        if let preferredWorkflowID,
           let match = workflows.first(where: { $0.id == preferredWorkflowID }) {
            return match
        }
        return workflows.first
    }

    func iconOverride(for worktreePath: String) -> SidebarItemIcon? {
        settings.worktreeIconOverrides[worktreePath]
    }

    func setIconOverride(_ icon: SidebarItemIcon?, for worktreePath: String) {
        settings.worktreeIconOverrides[worktreePath] = icon
    }

    func worktreeNote(for worktreePath: String) -> String? {
        let note = settings.worktreeNotes[worktreePath]
        if let note, note.isEmpty { return nil }
        return note
    }

    func setWorktreeNote(_ note: String?, for worktreePath: String) {
        if let note, !note.isEmpty {
            settings.worktreeNotes[worktreePath] = note
        } else {
            settings.worktreeNotes[worktreePath] = nil
        }
    }

    func pruneWorktreeCustomizations() {
        let validPaths = Set(worktrees.map(\.path))
        let prunedIcons = settings.worktreeIconOverrides.filter { validPaths.contains($0.key) }
        if prunedIcons.count != settings.worktreeIconOverrides.count {
            settings.worktreeIconOverrides = prunedIcons
        }
        let prunedNotes = settings.worktreeNotes.filter { validPaths.contains($0.key) }
        if prunedNotes.count != settings.worktreeNotes.count {
            settings.worktreeNotes = prunedNotes
        }
    }

    var paneOrder: [UUID] {
        layout?.paneIDs ?? []
    }

    var tabs: [WorkspaceTabStateRecord] {
        activeWorktreeState.tabs
    }

    var selectedTab: WorkspaceTabStateRecord? {
        activeWorktreeState.selectedTab
    }

    func bootstrapIfNeeded() {
        ensureActiveWorktreeState()
        guard !isArchived else { return }
        loadActiveWorktreeState()
    }

    func apply(snapshot: RepositorySnapshot) {
        guard supportsRepositoryFeatures else { return }
        saveActiveWorktreeState()
        let previousActiveWorktreePath = activeWorktreePath
        currentBranch = snapshot.currentBranch
        head = snapshot.head
        hasUncommittedChanges = snapshot.status.hasUncommittedChanges
        changedFileCount = snapshot.status.changedFileCount
        aheadCount = snapshot.status.aheadCount
        behindCount = snapshot.status.behindCount
        localBranches = snapshot.status.localBranches
        remoteBranches = snapshot.status.remoteBranches
        worktreeStatuses[activeWorktreePath] = snapshot.status
        worktrees = snapshot.worktrees
        if !worktrees.contains(where: { $0.path == activeWorktreePath }) {
            activeWorktreePath = snapshot.rootPath
        }
        ensureKnownWorktreeStates()
        pruneWorktreeCustomizations()
        if previousActiveWorktreePath != activeWorktreePath || layout == nil {
            loadActiveWorktreeState()
        }
    }

    func createPane(splitAxis: PaneSplitAxis?, snapshot: PaneSnapshot? = nil) {
        createPane(splitAxis: splitAxis, snapshot: snapshot, placement: .after)
    }

    func createPane(splitAxis: PaneSplitAxis?, snapshot: PaneSnapshot? = nil, placement: PaneSplitPlacement) {
        let targetPane = sessionController.focusedPaneID ?? layout?.firstPaneID
        let defaultSnapshot: PaneSnapshot = {
            var s = PaneSnapshot.makeDefault(cwd: activeWorktreePath)
            if let sshConfig = sshTarget {
                s.backendConfiguration = .ssh(sshConfig)
            }
            return s
        }()
        let newPaneID = sessionController.createPane(
            from: snapshot ?? defaultSnapshot
        )
        zoomedPaneID = nil

        guard let splitAxis, let layout else {
            self.layout = .pane(PaneLeaf(paneID: newPaneID))
            sessionController.focus(newPaneID)
            wireWorkspaceActions()
            saveActiveWorktreeState()
            return
        }

        var updatedLayout = layout
        if updatedLayout.split(
            paneID: targetPane ?? layout.firstPaneID ?? newPaneID,
            axis: splitAxis,
            newPaneID: newPaneID,
            placement: placement
        ) {
            self.layout = updatedLayout
        } else {
            self.layout = .split(
                PaneSplitNode(
                    axis: splitAxis,
                    first: placement == .before ? .pane(PaneLeaf(paneID: newPaneID)) : layout,
                    second: placement == .before ? layout : .pane(PaneLeaf(paneID: newPaneID))
                )
            )
        }
        sessionController.sync(with: paneOrder, defaultWorkingDirectory: activeWorktreePath)
        sessionController.focus(newPaneID)
        wireWorkspaceActions()
        saveActiveWorktreeState()
    }

    func closePane(_ paneID: UUID) {
        guard var layout else {
            sessionController.closePane(paneID)
            return
        }

        if case .pane(let leaf) = layout, leaf.paneID == paneID {
            self.layout = nil
            sessionController.closePane(paneID)
            if zoomedPaneID == paneID {
                zoomedPaneID = nil
            }
            saveActiveWorktreeState()
            return
        }

        _ = layout.removePane(paneID)
        self.layout = layout
        sessionController.closePane(paneID)
        if zoomedPaneID == paneID {
            zoomedPaneID = sessionController.focusedPaneID
        }
        sessionController.sync(with: paneOrder, defaultWorkingDirectory: activeWorktreePath)
        wireWorkspaceActions()
        if let first = paneOrder.first {
            sessionController.focus(first)
        }
        saveActiveWorktreeState()
    }

    func focusPane(_ paneID: UUID) {
        sessionController.focus(paneID)
        saveActiveWorktreeState()
    }

    func updateSplitFraction(splitID: UUID, fraction: Double) {
        guard var layout else { return }
        if layout.updateFraction(splitID: splitID, fraction: fraction) {
            self.layout = layout
            saveActiveWorktreeState()
        }
    }

    func resizeFocusedSplit(toward direction: PaneFocusDirection, amount: UInt16, paneID: UUID? = nil) {
        guard var layout else { return }
        let targetPaneID = paneID ?? sessionController.focusedPaneID
        guard let targetPaneID,
              layout.resizeSplit(containing: targetPaneID, toward: direction, amount: amount) else { return }
        self.layout = layout
        saveActiveWorktreeState()
    }

    func equalizeLayout() {
        guard var layout else { return }
        layout.equalizeSplits()
        self.layout = layout
        saveActiveWorktreeState()
    }

    func duplicateFocusedPane() {
        guard let focusedPaneID = sessionController.focusedPaneID else { return }
        let newPaneID = sessionController.duplicatePane(focusedPaneID, defaultWorkingDirectory: activeWorktreePath)
        guard let newPaneID else { return }
        zoomedPaneID = nil
        guard let currentLayout = layout else {
            layout = .pane(PaneLeaf(paneID: newPaneID))
            wireWorkspaceActions()
            saveActiveWorktreeState()
            return
        }

        var updatedLayout = currentLayout
        if updatedLayout.split(paneID: focusedPaneID, axis: .vertical, newPaneID: newPaneID) {
            layout = updatedLayout
        } else {
            layout = .split(PaneSplitNode(axis: .vertical, first: currentLayout, second: .pane(PaneLeaf(paneID: newPaneID))))
        }
        sessionController.sync(with: paneOrder, defaultWorkingDirectory: activeWorktreePath)
        sessionController.focus(newPaneID)
        wireWorkspaceActions()
        saveActiveWorktreeState()
    }

    func switchToWorktree(path: String, restartRunning: Bool) {
        saveActiveWorktreeState()
        activeWorktreePath = path
        ensureActiveWorktreeState()
        loadActiveWorktreeState()
        if restartRunning {
            sessionController.restartAll()
        }
    }

    func snapshot() -> WorkspaceRecord {
        saveActiveWorktreeState()
        return WorkspaceRecord(
            id: id,
            kind: kind,
            name: name,
            repositoryRoot: repositoryRoot,
            activeWorktreePath: activeWorktreePath,
            worktreeStates: worktreeStates.values.sorted { $0.worktreePath < $1.worktreePath },
            isSidebarExpanded: isSidebarExpanded,
            worktrees: worktrees,
            settings: settings,
            activityLog: activityLog,
            sshTarget: sshTarget
        )
    }

    var recentActivity: [WorkspaceActivityEntry] {
        activityLog.sorted { $0.timestamp > $1.timestamp }
    }

    func recordActivity(_ entry: WorkspaceActivityEntry, limit: Int = 120) {
        activityLog.insert(entry, at: 0)
        if activityLog.count > limit {
            activityLog = Array(activityLog.prefix(limit))
        }
    }

    func clearActivityLog() {
        activityLog.removeAll()
    }

    var activeWorktreeState: WorktreeSessionStateRecord {
        var state = worktreeStates[activeWorktreePath] ?? WorktreeSessionStateRecord.makeDefault(for: activeWorktreePath)
        state.ensureTabs()
        return state
    }

    func mergeWorktreeStatuses(_ statuses: [String: RepositoryStatusSnapshot]) {
        var changed = false
        for (path, status) in statuses {
            if worktreeStatuses[path] != status {
                worktreeStatuses[path] = status
                changed = true
            }
        }
        guard changed, let activeStatus = worktreeStatuses[activeWorktreePath] else { return }
        if hasUncommittedChanges != activeStatus.hasUncommittedChanges { hasUncommittedChanges = activeStatus.hasUncommittedChanges }
        if changedFileCount != activeStatus.changedFileCount { changedFileCount = activeStatus.changedFileCount }
        if aheadCount != activeStatus.aheadCount { aheadCount = activeStatus.aheadCount }
        if behindCount != activeStatus.behindCount { behindCount = activeStatus.behindCount }
    }

    func status(for worktreePath: String) -> RepositoryStatusSnapshot? {
        worktreeStatuses[worktreePath]
    }

    func gitHubStatus(for worktreePath: String) -> GitHubWorktreeStatus? {
        gitHubStatuses[worktreePath]
    }

    func updateGitHubStatus(_ status: GitHubWorktreeStatus?, for worktreePath: String) {
        gitHubStatuses[worktreePath] = status
    }

    func savedPaneCount(for worktreePath: String) -> Int {
        worktreeStates[worktreePath]?.tabs.reduce(0) { $0 + $1.panes.count } ?? 0
    }

    func paneCount(for tabID: UUID) -> Int {
        if activeTabID == tabID {
            return paneOrder.count
        }
        return activeWorktreeState.tabs.first(where: { $0.id == tabID })?.panes.count ?? 0
    }

    func paneCount(for tabID: UUID, worktreePath: String) -> Int {
        if activeWorktreePath == worktreePath, activeTabID == tabID {
            return paneOrder.count
        }
        return worktreeStates[worktreePath]?.tabs.first(where: { $0.id == tabID })?.panes.count ?? 0
    }

    func tabController(for tabID: UUID) -> WorkspaceSessionController? {
        guard let tab = activeWorktreeState.tabs.first(where: { $0.id == tabID }) else { return nil }
        return controller(for: activeWorktreePath, tabState: tab)
    }

    func existingTabController(for worktreePath: String, tabID: UUID) -> WorkspaceSessionController? {
        worktreeControllers[worktreePath]?[tabID]
    }

    func canvasStates() -> [WorktreeSessionStateRecord] {
        worktreeStates.values.sorted { lhs, rhs in
            if lhs.worktreePath == activeWorktreePath, rhs.worktreePath != activeWorktreePath {
                return true
            }
            if lhs.worktreePath != activeWorktreePath, rhs.worktreePath == activeWorktreePath {
                return false
            }
            return lhs.worktreePath.localizedStandardCompare(rhs.worktreePath) == .orderedAscending
        }
    }

    func isActiveCanvasCard(worktreePath: String, tabID: UUID) -> Bool {
        activeWorktreePath == worktreePath && activeTabID == tabID
    }

    func canvasCardIDs() -> [GlobalCanvasCardID] {
        canvasStates().flatMap { state in
            state.tabs.map { tab in
                GlobalCanvasCardID(
                    workspaceID: id,
                    worktreePath: state.worktreePath,
                    tabID: tab.id
                )
            }
        }
    }

    func activeSessionCount(forWorktreePath path: String) -> Int {
        worktreeControllers[path]?.values.reduce(0) { partialResult, controller in
            partialResult + controller.activeSessionCount(using: path)
        } ?? 0
    }

    func runningSessionCount(forWorktreePath path: String) -> Int {
        worktreeControllers[path]?.values.reduce(0) { partialResult, controller in
            partialResult + controller.runningSessionCount(using: path)
        } ?? 0
    }

    func createTab() {
        saveActiveWorktreeState()
        var state = activeWorktreeState
        let newIndex = state.tabs.count + 1
        let newTab = WorkspaceTabStateRecord.makeDefault(
            for: activeWorktreePath,
            title: "Tab \(newIndex)"
        )
        state.upsertTab(newTab, selecting: true)
        worktreeStates[activeWorktreePath] = state
        loadActiveWorktreeState()
    }

    func selectTab(_ tabID: UUID) {
        guard tabID != activeTabID else { return }
        saveActiveWorktreeState()
        var state = activeWorktreeState
        state.setSelectedTabID(tabID)
        worktreeStates[activeWorktreePath] = state
        loadActiveWorktreeState()
    }

    func selectTab(at index: Int) {
        let state = activeWorktreeState
        guard let tabID = state.tabID(at: index) else { return }
        selectTab(tabID)
    }

    func selectNextTab() {
        let state = activeWorktreeState
        guard !state.tabs.isEmpty else { return }
        guard let activeTabID,
              let index = state.tabs.firstIndex(where: { $0.id == activeTabID }) else {
            selectTab(state.tabs[0].id)
            return
        }
        selectTab(state.tabs[(index + 1) % state.tabs.count].id)
    }

    func selectPreviousTab() {
        let state = activeWorktreeState
        guard !state.tabs.isEmpty else { return }
        guard let activeTabID,
              let index = state.tabs.firstIndex(where: { $0.id == activeTabID }) else {
            selectTab(state.tabs[0].id)
            return
        }
        selectTab(state.tabs[(index - 1 + state.tabs.count) % state.tabs.count].id)
    }

    func closeTab(_ tabID: UUID) {
        saveActiveWorktreeState()
        var state = activeWorktreeState

        guard state.tabs.contains(where: { $0.id == tabID }) else { return }
        if state.tabs.count == 1 {
            let replacement = WorkspaceTabStateRecord.makeDefault(for: activeWorktreePath)
            state = WorktreeSessionStateRecord(
                worktreePath: activeWorktreePath,
                layout: replacement.layout,
                panes: replacement.panes,
                focusedPaneID: replacement.focusedPaneID,
                zoomedPaneID: replacement.zoomedPaneID,
                tabs: [replacement],
                selectedTabID: replacement.id
            )
        } else {
            let tabs = state.tabs
            let currentIndex = tabs.firstIndex(where: { $0.id == tabID }) ?? 0
            state.removeTab(tabID)
            let fallbackIndex = min(currentIndex, max(state.tabs.count - 1, 0))
            state.setSelectedTabID(state.tabs[fallbackIndex].id)
        }

        if var controllers = worktreeControllers[activeWorktreePath] {
            controllers.removeValue(forKey: tabID)?.sessions.values.forEach { $0.terminate() }
            worktreeControllers[activeWorktreePath] = controllers
        }

        worktreeStates[activeWorktreePath] = state
        loadActiveWorktreeState()
    }

    func renameTab(_ tabID: UUID, title: String) {
        saveActiveWorktreeState()
        var state = activeWorktreeState
        state.renameTab(tabID, title: title)
        worktreeStates[activeWorktreePath] = state
        loadActiveWorktreeState()
    }

    func moveTabLeft(_ tabID: UUID) {
        moveTab(tabID, by: -1)
    }

    func moveTabRight(_ tabID: UUID) {
        moveTab(tabID, by: 1)
    }

    func moveTab(_ tabID: UUID, to index: Int) {
        saveActiveWorktreeState()
        var state = activeWorktreeState
        state.moveTab(tabID, to: index)
        worktreeStates[activeWorktreePath] = state
        loadActiveWorktreeState()
    }

    func focusPane(in direction: PaneFocusDirection) {
        guard let layout, let current = sessionController.focusedPaneID else { return }
        guard let target = layout.paneID(in: direction, from: current) else { return }
        focusPane(target)
    }

    func toggleZoom(on paneID: UUID? = nil) {
        let target = paneID ?? sessionController.focusedPaneID
        guard let target else { return }
        if zoomedPaneID == target {
            zoomedPaneID = nil
        } else {
            zoomedPaneID = target
            focusPane(target)
        }
        saveActiveWorktreeState()
    }

    func focusLastPane() {
        guard let previousFocusedPaneID = sessionController.previousFocusedPaneID else { return }
        focusPane(previousFocusedPaneID)
    }

    func closeAllPanes() {
        sessionController.sessions.keys.forEach { sessionController.closePane($0) }
        let initialPane = sessionController.createPane(defaultWorkingDirectory: activeWorktreePath)
        layout = .pane(PaneLeaf(paneID: initialPane))
        zoomedPaneID = nil
        sessionController.sync(with: [initialPane], defaultWorkingDirectory: activeWorktreePath)
        sessionController.focus(initialPane)
        wireWorkspaceActions()
        saveActiveWorktreeState()
    }

    func restartAllPanes() {
        sessionController.restartAll()
        saveActiveWorktreeState()
    }

    func resetLayout() {
        closeAllPanes()
    }

    func forgetWorktrees(paths: [String]) {
        let targets = Set(paths)
        guard !targets.isEmpty else { return }

        if targets.contains(activeWorktreePath) {
            activeWorktreePath = repositoryRoot
        }

        for path in targets {
            worktreeStates.removeValue(forKey: path)
            let controllers = worktreeControllers.removeValue(forKey: path)?.map(\.value) ?? []
            for controller in controllers {
                controller.sessions.values.forEach { $0.terminate() }
            }
            worktreeStatuses.removeValue(forKey: path)
        }

        ensureActiveWorktreeState()
        loadActiveWorktreeState()
        saveActiveWorktreeState()
    }

    func prepareForWorktreeRemoval(paths: [String]) {
        let targets = Set(paths)
        guard !targets.isEmpty else { return }

        saveActiveWorktreeState()

        if targets.contains(activeWorktreePath) {
            activeWorktreePath = repositoryRoot
            ensureActiveWorktreeState()
            loadActiveWorktreeState()
        }

        for path in targets {
            let controllers = worktreeControllers[path]?.map(\.value) ?? []
            for controller in controllers {
                controller.sessions.values.forEach { $0.terminate() }
            }
        }
    }

    private func saveActiveWorktreeState() {
        var state = activeWorktreeState
        let tabID = activeTabID ?? state.selectedTabID ?? state.tabs.first?.id ?? UUID()
        let existingTab = state.tabs.first(where: { $0.id == tabID })
        let preferredTitle = suggestedTitle(for: sessionController, existingTab: existingTab)
        state.upsertTab(
            WorkspaceTabStateRecord(
                id: tabID,
                title: preferredTitle,
                isManuallyNamed: existingTab?.isManuallyNamed == true,
                layout: layout,
                panes: sessionController.sessionSnapshots(in: paneOrder),
                focusedPaneID: sessionController.focusedPaneID,
                zoomedPaneID: zoomedPaneID
            ),
            selecting: true
        )
        worktreeStates[activeWorktreePath] = state
    }

    private func loadActiveWorktreeState() {
        ensureActiveWorktreeState()
        let state = activeWorktreeState
        let tab = state.selectedTab ?? WorkspaceTabStateRecord.makeDefault(for: activeWorktreePath)
        activeTabID = tab.id
        layout = tab.layout
        let controller = controller(for: activeWorktreePath, tabState: tab)
        sessionController = controller
        zoomedPaneID = tab.zoomedPaneID
        if layout == nil {
            var initialSnapshot = PaneSnapshot.makeDefault(cwd: activeWorktreePath)
            if let sshConfig = sshTarget {
                initialSnapshot.backendConfiguration = .ssh(sshConfig)
            }
            let initialPane = controller.createPane(from: initialSnapshot)
            layout = .pane(PaneLeaf(paneID: initialPane))
        }
        if !isArchived {
            controller.sync(with: paneOrder, defaultWorkingDirectory: activeWorktreePath)
        }
        wireWorkspaceActions()
        saveActiveWorktreeState()
    }

    private func ensureActiveWorktreeState() {
        if worktreeStates[activeWorktreePath] == nil {
            worktreeStates[activeWorktreePath] = WorktreeSessionStateRecord.makeDefault(for: activeWorktreePath)
        }
        worktreeStates[activeWorktreePath]?.ensureTabs()
    }

    func ensureKnownWorktreeStates() {
        for worktree in worktrees {
            if worktreeStates[worktree.path] == nil {
                worktreeStates[worktree.path] = WorktreeSessionStateRecord.makeDefault(for: worktree.path)
            }
            worktreeStates[worktree.path]?.ensureTabs()
        }
    }

    private func controller(for worktreePath: String, tabState: WorkspaceTabStateRecord) -> WorkspaceSessionController {
        if let existing = worktreeControllers[worktreePath]?[tabState.id] {
            existing.sync(with: tabState.layout?.paneIDs ?? tabState.panes.map(\.id), defaultWorkingDirectory: worktreePath)
            if let focusedPaneID = tabState.focusedPaneID {
                existing.focusedPaneID = focusedPaneID
            }
            wireWorkspaceActions()
            return existing
        }

        let controller = WorkspaceSessionController(workspaceID: id, paneSnapshots: tabState.panes)
        controller.focusedPaneID = tabState.focusedPaneID
        var controllers = worktreeControllers[worktreePath] ?? [:]
        controllers[tabState.id] = controller
        worktreeControllers[worktreePath] = controllers
        wireWorkspaceActions()
        return controller
    }

    private func moveTab(_ tabID: UUID, by offset: Int) {
        saveActiveWorktreeState()
        var state = activeWorktreeState
        state.moveTab(tabID, by: offset)
        worktreeStates[activeWorktreePath] = state
        loadActiveWorktreeState()
    }

    private func suggestedTitle(for controller: WorkspaceSessionController, existingTab: WorkspaceTabStateRecord?) -> String {
        if existingTab?.isManuallyNamed == true {
            return existingTab?.title ?? "Tab"
        }
        if let focusedPaneID = controller.focusedPaneID,
           let session = controller.session(for: focusedPaneID) {
            let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
            let directory = session.effectiveWorkingDirectory.lastPathComponentValue
            if !directory.isEmpty {
                return directory
            }
        }
        return existingTab?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Tab"
    }

    private func wireWorkspaceActions() {
        for (paneID, session) in sessionController.sessions {
            session.onWorkspaceAction = { [weak self] action in
                self?.handleWorkspaceAction(action, paneID: paneID)
            }
            session.onFocus = { [weak self] in
                guard let self, self.sessionController.focusedPaneID != paneID else { return }
                self.focusPane(paneID)
            }
        }
    }

    private func handleWorkspaceAction(_ action: TerminalWorkspaceAction, paneID: UUID) {
        switch action {
        case .createSplit(let axis, let placement):
            focusPane(paneID)
            createPane(splitAxis: axis, placement: placement)
        case .focusPane(let direction):
            focusPane(in: direction)
        case .focusNextPane:
            sessionController.focusNext(using: paneOrder)
            saveActiveWorktreeState()
        case .focusPreviousPane:
            sessionController.focusPrevious(using: paneOrder)
            saveActiveWorktreeState()
        case .resizeFocusedSplit(let direction, let amount):
            focusPane(paneID)
            resizeFocusedSplit(toward: direction, amount: amount, paneID: paneID)
        case .equalizeSplits:
            equalizeLayout()
        case .togglePaneZoom:
            toggleZoom(on: paneID)
        case .closePane:
            closePane(paneID)
        case .desktopNotification(let title):
            let item = IslandNotificationItem(
                id: UUID(),
                workspaceID: id,
                worktreePath: activeWorktreePath,
                title: title,
                agentName: nil,
                terminalTag: nil,
                status: .running,
                startedAt: Date(),
                body: nil,
                prompt: nil
            )
            IslandNotificationState.shared.post(item: item)
            IslandPanelController.shared.show()
        }
    }
}
