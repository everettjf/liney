//
//  WorkspaceStore.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let lineyAppSettingsDidChange = Notification.Name("liney.appSettingsDidChange")
}

@MainActor
final class WorkspaceStore: ObservableObject {
    private let activityLogLimit = 120

    @Published var workspaces: [WorkspaceModel] = []
    @Published var selectedWorkspaceID: UUID?
    @Published var appSettings = AppSettings()
    @Published var gitHubIntegrationState: GitHubIntegrationState = .disabled
    @Published var statusMessage: WorkspaceStatusMessage?
    @Published var isOverviewPresented = false
    @Published var globalCanvasState = GlobalCanvasStateRecord()
    @Published var isCommandPalettePresented = false
    @Published var commandPaletteQuery = ""
    @Published var selectedCommandPaletteItemID: String?
    @Published var settingsRequest: WorkspaceSettingsRequest?
    @Published var quickCommandEditorRequest: QuickCommandEditorRequest?
    @Published var sidebarIconCustomizationRequest: SidebarIconCustomizationRequest?
    @Published var presentedError: PresentedError?
    @Published var renameWorkspaceRequest: RenameWorkspaceRequest?
    @Published var createWorktreeRequest: CreateWorktreeSheetRequest?
    @Published var createSSHSessionRequest: CreateSSHSessionRequest?
    @Published var createAgentSessionRequest: CreateAgentSessionRequest?
    @Published var pendingWorktreeSwitch: PendingWorktreeSwitch?
    @Published var pendingWorktreeRemoval: PendingWorktreeRemoval?
    @Published var sleepPreventionSession: SleepPreventionSession?
    @Published private(set) var sleepPreventionQuickActionOption: SleepPreventionDurationOption = .oneHour
    @Published private(set) var sleepPreventionReferenceDate = Date()

    private let persistence = WorkspaceStatePersistence()
    private let appSettingsPersistence = AppSettingsPersistence()
    private let initialWorkspaceState: PersistedWorkspaceState?
    private let initialAppSettings: AppSettings?
    private let gitRepositoryService = GitRepositoryService()
    private let updaterController = AppUpdaterController()
    private let remoteSessionCoordinator = RemoteSessionCoordinator()
    private let metadataWatchService = WorkspaceMetadataWatchService()
    private let sleepPreventionController = SleepPreventionController()
    private var persistsWorkspaceState: Bool
    private var hasLoaded = false
    private var hasConfiguredUpdater = false
    private var autoRefreshTask: Task<Void, Never>?
    private var statusMessageTask: Task<Void, Never>?
    private var sleepPreventionTickerTask: Task<Void, Never>?

    init(
        initialWorkspaceState: PersistedWorkspaceState? = nil,
        initialAppSettings: AppSettings? = nil,
        persistsWorkspaceState: Bool = true
    ) {
        self.initialWorkspaceState = initialWorkspaceState
        self.initialAppSettings = initialAppSettings
        self.persistsWorkspaceState = persistsWorkspaceState
        sleepPreventionController.onEvent = { [weak self] event in
            self?.handleSleepPreventionEvent(event)
        }
    }

    var currentReleaseVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "0.0.0"
    }

    var currentReleaseBuild: String? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var selectedWorkspace: WorkspaceModel? {
        guard let selectedWorkspaceID else { return workspaces.first }
        return workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces.first
    }

    var sidebarWorkspaces: [WorkspaceModel] {
        let visible = workspaces.filter { appSettings.showArchivedWorkspaces || !$0.isArchived }
        return visible.enumerated().sorted { lhs, rhs in
            if lhs.element.isPinned != rhs.element.isPinned {
                return lhs.element.isPinned && !rhs.element.isPinned
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    var availableExternalEditors: [ExternalEditorDescriptor] {
        ExternalEditorCatalog.availableEditors()
    }

    var effectiveExternalEditor: ExternalEditorDescriptor? {
        ExternalEditorCatalog.effectiveEditor(
            preferred: appSettings.preferredExternalEditor,
            among: availableExternalEditors
        )
    }

    var quickCommandPresets: [QuickCommandPreset] {
        appSettings.quickCommandPresets
    }

    var quitConfirmationSessionCount: Int {
        workspaces.reduce(0) { $0 + $1.quitConfirmationSessionCount }
    }

    var recentQuickCommandPresets: [QuickCommandPreset] {
        let commandsByID = Dictionary(uniqueKeysWithValues: quickCommandPresets.map { ($0.id, $0) })
        return appSettings.quickCommandRecentIDs.compactMap { commandsByID[$0] }
    }

    var sleepPreventionOptions: [SleepPreventionDurationOption] {
        SleepPreventionDurationOption.allCases
    }

    var sleepPreventionStatusText: String {
        guard let sleepPreventionSession else {
            return "Do Not Sleep"
        }
        return "Do Not Sleep: \(sleepPreventionSession.remainingDescription(relativeTo: sleepPreventionReferenceDate))"
    }

    var sleepPreventionPrimaryActionLabel: String {
        sleepPreventionSession == nil ? "Start Do Not Sleep" : "Stop Do Not Sleep"
    }

    var sleepPreventionPrimaryActionHelpText: String {
        if let sleepPreventionSession {
            return "Stop macOS sleep prevention (\(sleepPreventionSession.remainingDescription(relativeTo: sleepPreventionReferenceDate)))"
        }
        return "Prevent macOS sleep for \(sleepPreventionQuickActionOption.title)"
    }

    var commandPaletteItems: [CommandPaletteItem] {
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let recencyByID = appSettings.commandPaletteRecents
        let ranked = allCommandPaletteItems
            .compactMap { item -> (CommandPaletteItem, Double)? in
                guard let score = item.score(query: query, recency: recencyByID[item.id]) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)

        if query.isEmpty {
            return ranked.filter { $0.group != .recent }
        }
        return ranked
    }

    var commandPaletteSections: [CommandPaletteSection] {
        let items = commandPaletteItems
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var remaining = items
        var sections: [CommandPaletteSection] = []

        if query.isEmpty {
            let recentIDs = Set(
                remaining
                    .filter { appSettings.commandPaletteRecents[$0.id] != nil }
                    .prefix(6)
                    .map(\.id)
            )
            let recentItems = remaining.filter { recentIDs.contains($0.id) }
            if !recentItems.isEmpty {
                sections.append(CommandPaletteSection(group: .recent, items: recentItems))
                remaining.removeAll { recentIDs.contains($0.id) }
            }
        }

        for group in CommandPaletteGroup.allCases where group != .recent {
            let groupItems = remaining.filter { $0.group == group }
            if !groupItems.isEmpty {
                sections.append(CommandPaletteSection(group: group, items: groupItems))
            }
        }
        return sections
    }

    private var allCommandPaletteItems: [CommandPaletteItem] {
        var items: [CommandPaletteItem] = [
            CommandPaletteItem(
                id: "overview",
                title: isOverviewPresented ? "Close Workspace Overview" : "Open Workspace Overview",
                subtitle: "\(workspaces.count) workspaces",
                group: .navigation,
                keywords: ["overview", "dashboard", "summary"],
                isGlobal: true,
                kind: .command(.toggleOverview)
            ),
            CommandPaletteItem(
                id: "settings",
                title: "Open Settings",
                subtitle: nil,
                group: .navigation,
                keywords: ["preferences", "configuration"],
                isGlobal: true,
                kind: .command(.presentSettings)
            ),
            CommandPaletteItem(
                id: "refresh-all",
                title: "Refresh All Repositories",
                subtitle: nil,
                group: .automation,
                keywords: ["reload", "sync", "repositories"],
                isGlobal: true,
                kind: .command(.refreshAllRepositories)
            ),
            CommandPaletteItem(
                id: "toggle-archived",
                title: appSettings.showArchivedWorkspaces ? "Hide Archived Workspaces" : "Show Archived Workspaces",
                subtitle: nil,
                group: .navigation,
                keywords: ["archive", "sidebar"],
                isGlobal: true,
                kind: .command(.toggleShowArchived)
            ),
            CommandPaletteItem(
                id: "check-updates",
                title: "Check for Liney Updates",
                subtitle: "Sparkle automatic updates",
                group: .releases,
                keywords: ["release", "update", "version", "sparkle"],
                isGlobal: true,
                kind: .command(.checkForUpdates)
            ),
            CommandPaletteItem(
                id: "open-latest-release",
                title: "Open Latest Release",
                subtitle: "Release notes and download details",
                group: .releases,
                keywords: ["release", "notes", "download"],
                isGlobal: true,
                kind: .command(.openLatestRelease)
            ),
        ]

        if let selectedWorkspace {
            items.append(
                CommandPaletteItem(
                    id: "workspace-selected-session:\(selectedWorkspace.id.uuidString)",
                    title: "New Session in \(selectedWorkspace.name)",
                    subtitle: selectedWorkspace.activeWorktreePath,
                    group: .sessions,
                    keywords: ["terminal", "pane", "shell"],
                    isGlobal: false,
                    kind: .command(.createSession(selectedWorkspace.id))
                )
            )
            items.append(
                CommandPaletteItem(
                    id: "workspace-selected-split-right:\(selectedWorkspace.id.uuidString)",
                    title: "Split Right in \(selectedWorkspace.name)",
                    subtitle: selectedWorkspace.currentBranch,
                    group: .sessions,
                    keywords: ["pane", "vertical", "split"],
                    isGlobal: false,
                    kind: .command(.splitFocusedPane(selectedWorkspace.id, .vertical))
                )
            )
            items.append(
                CommandPaletteItem(
                    id: "workspace-selected-split-down:\(selectedWorkspace.id.uuidString)",
                    title: "Split Down in \(selectedWorkspace.name)",
                    subtitle: selectedWorkspace.currentBranch,
                    group: .sessions,
                    keywords: ["pane", "horizontal", "split"],
                    isGlobal: false,
                    kind: .command(.splitFocusedPane(selectedWorkspace.id, .horizontal))
                )
            )
            if !selectedWorkspace.setupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-selected-setup:\(selectedWorkspace.id.uuidString)",
                        title: "Run Setup Script in \(selectedWorkspace.name)",
                        subtitle: selectedWorkspace.setupScript,
                        group: .automation,
                        keywords: ["bootstrap", "install", "setup"],
                        isGlobal: false,
                        kind: .command(.runSetupScript(selectedWorkspace.id))
                    )
                )
            }
            if let workflow = selectedWorkspace.preferredWorkflow {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-selected-workflow:\(selectedWorkspace.id.uuidString)",
                        title: "Run Preferred Workflow in \(selectedWorkspace.name)",
                        subtitle: workflow.name,
                        group: .workflows,
                        keywords: ["playbook", "workflow", "automation"],
                        isGlobal: false,
                        kind: .command(.runWorkflow(selectedWorkspace.id, workflow.id))
                    )
                )
            }
        }

        for workspace in workspaces {
            items.append(
                CommandPaletteItem(
                    id: "workspace:\(workspace.id.uuidString)",
                    title: "Open \(workspace.name)",
                    subtitle: workspace.activeWorktreePath,
                    group: .navigation,
                    keywords: ["workspace", "focus", "select"],
                    isGlobal: false,
                    kind: .command(.selectWorkspace(workspace.id))
                )
            )
            items.append(
                CommandPaletteItem(
                    id: "workspace-refresh:\(workspace.id.uuidString)",
                    title: "Refresh \(workspace.name)",
                    subtitle: workspace.currentBranch,
                    group: .automation,
                    keywords: ["reload", "fetch", "sync"],
                    isGlobal: false,
                    kind: .command(.refreshWorkspace(workspace.id))
                )
            )
            items.append(
                CommandPaletteItem(
                    id: "workspace-session:\(workspace.id.uuidString)",
                    title: "New Session in \(workspace.name)",
                    subtitle: workspace.activeWorktreePath,
                    group: .sessions,
                    keywords: ["terminal", "pane", "shell"],
                    isGlobal: false,
                    kind: .command(.createSession(workspace.id))
                )
            )
            for remoteTarget in workspace.remoteTargets {
                items.append(
                    CommandPaletteItem(
                        id: "remote-shell:\(workspace.id.uuidString):\(remoteTarget.id.uuidString)",
                        title: "Open Remote Shell: \(remoteTarget.name)",
                        subtitle: remoteTarget.ssh.destination,
                        group: .sessions,
                        keywords: ["ssh", "remote", "shell", workspace.name],
                        isGlobal: false,
                        kind: .command(.openRemoteTargetShell(workspace.id, remoteTarget.id))
                    )
                )
                if let presetID = remoteTarget.agentPresetID,
                   let preset = workspace.agentPresets.first(where: { $0.id == presetID }) {
                    items.append(
                        CommandPaletteItem(
                            id: "remote-agent:\(workspace.id.uuidString):\(remoteTarget.id.uuidString)",
                            title: "Launch Remote Agent: \(remoteTarget.name)",
                            subtitle: preset.name,
                            group: .sessions,
                            keywords: ["ssh", "remote", "agent", "codex", workspace.name],
                            isGlobal: false,
                            kind: .command(.openRemoteTargetAgent(workspace.id, remoteTarget.id))
                        )
                    )
                }
            }
            items.append(
                CommandPaletteItem(
                    id: "workspace-pin:\(workspace.id.uuidString)",
                    title: workspace.isPinned ? "Unpin \(workspace.name)" : "Pin \(workspace.name)",
                    subtitle: nil,
                    group: .navigation,
                    keywords: ["sidebar", "favorite"],
                    isGlobal: false,
                    kind: .command(.toggleWorkspacePinned(workspace.id))
                )
            )
            items.append(
                CommandPaletteItem(
                    id: "workspace-archive:\(workspace.id.uuidString)",
                    title: workspace.isArchived ? "Unarchive \(workspace.name)" : "Archive \(workspace.name)",
                    subtitle: nil,
                    group: .navigation,
                    keywords: ["hide", "archive"],
                    isGlobal: false,
                    kind: .command(.toggleWorkspaceArchived(workspace.id))
                )
            )
            if workspace.supportsRepositoryFeatures {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-worktree:\(workspace.id.uuidString)",
                        title: "Create Worktree in \(workspace.name)",
                        subtitle: workspace.repositoryRoot,
                        group: .sessions,
                        keywords: ["branch", "git", "worktree"],
                        isGlobal: false,
                        kind: .command(.createWorktree(workspace.id))
                    )
                )
            }
            if LineyFeatureFlags.showsRemoteSessionCreationUI {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-ssh:\(workspace.id.uuidString)",
                        title: "New SSH Session in \(workspace.name)",
                        subtitle: nil,
                        group: .sessions,
                        keywords: ["remote", "server", "ssh"],
                        isGlobal: false,
                        kind: .command(.createSSHSession(workspace.id))
                    )
                )
                items.append(
                    CommandPaletteItem(
                        id: "workspace-agent:\(workspace.id.uuidString)",
                        title: "New Agent Session in \(workspace.name)",
                        subtitle: workspace.agentPresets.first?.name,
                        group: .sessions,
                        keywords: ["ai", "agent", "codex"],
                        isGlobal: false,
                        kind: .command(.createAgentSession(workspace.id, workspace.preferredAgentPreset))
                    )
                )
            }
            if !workspace.setupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-setup:\(workspace.id.uuidString)",
                        title: "Run Setup Script in \(workspace.name)",
                        subtitle: workspace.setupScript,
                        group: .automation,
                        keywords: ["bootstrap", "install", "prepare"],
                        isGlobal: false,
                        kind: .command(.runSetupScript(workspace.id))
                    )
                )
            }
            if !workspace.runScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-run:\(workspace.id.uuidString)",
                        title: "Run Script in \(workspace.name)",
                        subtitle: workspace.runScript,
                        group: .automation,
                        keywords: ["build", "start", "run"],
                        isGlobal: false,
                        kind: .command(.runWorkspaceScript(workspace.id))
                    )
                )
            }
            for workflow in workspace.workflows {
                items.append(
                    CommandPaletteItem(
                        id: "workflow:\(workspace.id.uuidString):\(workflow.id.uuidString)",
                        title: "Run Workflow: \(workflow.name)",
                        subtitle: workspace.name,
                        group: .workflows,
                        keywords: ["playbook", "workflow", workspace.name],
                        isGlobal: false,
                        kind: .command(.runWorkflow(workspace.id, workflow.id))
                    )
                )
            }
        }

        return items
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        appSettings = initialAppSettings ?? appSettingsPersistence.load()
        appSettings.githubIntegrationEnabled = false
        NotificationCenter.default.post(name: .lineyAppSettingsDidChange, object: appSettings)
        let state = normalizeLaunchState(initialWorkspaceState ?? persistence.load())
        workspaces = state.workspaces.map(WorkspaceModel.init(record:))
        globalCanvasState = state.globalCanvasState.pruned(to: validGlobalCanvasCardIDs(in: workspaces))
        ensureDefaultWorkspace()
        removeDefaultLocalWorkspaceIfNeeded()
        selectedWorkspaceID = state.selectedWorkspaceID ?? workspaces.first?.id

        for workspace in workspaces {
            if workspace.supportsRepositoryFeatures {
                await refreshWorkspace(workspace, persistAfterRefresh: false)
            } else {
                workspace.bootstrapIfNeeded()
            }
        }

        configureUpdater(checkInBackground: true)
        syncAutomationServices()
        persist()
    }

    func addWorkspaceFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Workspace"
        panel.message = "Choose a local git repository."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await addWorkspace(at: url)
        }
    }

    func addWorkspace(at url: URL) async {
        do {
            let snapshot = try await gitRepositoryService.inspectRepository(at: url.path)
            if let existing = workspaces.first(where: { $0.repositoryRoot == snapshot.rootPath }) {
                selectedWorkspaceID = existing.id
                await refreshWorkspace(existing)
                return
            }

            let workspace = WorkspaceModel(snapshot: snapshot)
            let existingRepositoryIcons = workspaces
                .filter(\.supportsRepositoryFeatures)
                .map(sidebarIcon(for:))
            workspace.workspaceIconOverride = .randomRepository(
                preferredSeed: workspace.name,
                avoiding: existingRepositoryIcons
            )
            workspaces.append(workspace)
            selectedWorkspaceID = workspace.id
            removeDefaultLocalWorkspaceIfNeeded()
            configureMetadataWatchers()
            persist()
        } catch {
            presentError(title: "Unable to Add Workspace", message: error.localizedDescription)
        }
    }

    func removeWorkspace(_ workspace: WorkspaceModel) {
        workspace.sessionController.sessions.values.forEach { $0.terminate() }
        workspaces.removeAll(where: { $0.id == workspace.id })
        if selectedWorkspaceID == workspace.id {
            selectedWorkspaceID = workspaces.first?.id
        }
        ensureDefaultWorkspace()
        configureMetadataWatchers()
        persist()
    }

    func removeWorkspaces(ids: [UUID]) {
        let selectedIDs = Set(ids)
        let targets = workspaces.filter { selectedIDs.contains($0.id) }
        for workspace in targets {
            workspace.sessionController.sessions.values.forEach { $0.terminate() }
        }
        workspaces.removeAll { selectedIDs.contains($0.id) }
        if let selectedWorkspaceID, selectedIDs.contains(selectedWorkspaceID) {
            self.selectedWorkspaceID = workspaces.first?.id
        }
        ensureDefaultWorkspace()
        configureMetadataWatchers()
        persist()
    }

    func selectWorkspace(_ workspace: WorkspaceModel) {
        selectedWorkspaceID = workspace.id
        workspace.bootstrapIfNeeded()
        persist()
    }

    func selectGlobalCanvasCard(_ cardID: GlobalCanvasCardID) {
        guard let workspace = workspace(for: cardID.workspaceID) else { return }
        selectedWorkspaceID = workspace.id
        workspace.bootstrapIfNeeded()
        if workspace.activeWorktreePath != cardID.worktreePath {
            workspace.switchToWorktree(path: cardID.worktreePath, restartRunning: false)
        }
        workspace.selectTab(cardID.tabID)
        persist()
    }

    func updateGlobalCanvasState(_ canvasState: GlobalCanvasStateRecord) {
        let prunedState = canvasState.pruned(to: validGlobalCanvasCardIDs())
        guard prunedState != globalCanvasState else { return }
        globalCanvasState = prunedState
        persist()
    }

    func requestRenameWorkspace(_ workspace: WorkspaceModel) {
        renameWorkspaceRequest = RenameWorkspaceRequest(workspaceID: workspace.id, currentName: workspace.name)
    }

    func renameWorkspace(id: UUID, to newName: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.name = trimmed
        persist()
    }

    func presentSettings(for workspace: WorkspaceModel? = nil) {
        settingsRequest = WorkspaceSettingsRequest(workspaceID: workspace?.id)
    }

    func presentQuickCommandEditor() {
        quickCommandEditorRequest = QuickCommandEditorRequest()
    }

    func presentSidebarIconCustomization(for workspace: WorkspaceModel) {
        sidebarIconCustomizationRequest = SidebarIconCustomizationRequest(target: .workspace(workspace.id))
    }

    func presentSidebarIconCustomization(for worktree: WorktreeModel, in workspace: WorkspaceModel) {
        sidebarIconCustomizationRequest = SidebarIconCustomizationRequest(
            target: .worktree(workspaceID: workspace.id, worktreePath: worktree.path)
        )
    }

    func presentSidebarIconCustomization(for target: SidebarIconCustomizationTarget) {
        sidebarIconCustomizationRequest = SidebarIconCustomizationRequest(target: target)
    }

    func updateAppSettings(_ settings: AppSettings) {
        let wasAutoCheckEnabled = appSettings.autoCheckForUpdates
        appSettings = AppSettings(
            autoRefreshEnabled: settings.autoRefreshEnabled,
            autoRefreshIntervalSeconds: settings.autoRefreshIntervalSeconds,
            autoClosePaneOnProcessExit: settings.autoClosePaneOnProcessExit,
            confirmQuitWhenCommandsRunning: settings.confirmQuitWhenCommandsRunning,
            hotKeyWindowEnabled: settings.hotKeyWindowEnabled,
            hotKeyWindowShortcut: settings.hotKeyWindowShortcut,
            fileWatcherEnabled: settings.fileWatcherEnabled,
            githubIntegrationEnabled: false,
            autoCheckForUpdates: settings.autoCheckForUpdates,
            autoDownloadUpdates: settings.autoDownloadUpdates,
            systemNotificationsEnabled: settings.systemNotificationsEnabled,
            showArchivedWorkspaces: settings.showArchivedWorkspaces,
            sidebarShowsSecondaryLabels: settings.sidebarShowsSecondaryLabels,
            sidebarShowsWorkspaceBadges: settings.sidebarShowsWorkspaceBadges,
            sidebarShowsWorktreeBadges: settings.sidebarShowsWorktreeBadges,
            defaultRepositoryIcon: settings.defaultRepositoryIcon,
            defaultLocalTerminalIcon: settings.defaultLocalTerminalIcon,
            defaultWorktreeIcon: settings.defaultWorktreeIcon,
            preferredExternalEditor: settings.preferredExternalEditor,
            quickCommandPresets: settings.quickCommandPresets,
            quickCommandRecentIDs: settings.quickCommandRecentIDs,
            releaseChannel: settings.releaseChannel,
            commandPaletteRecents: settings.commandPaletteRecents,
            keyboardShortcutOverrides: settings.keyboardShortcutOverrides
        )
        for workspace in workspaces {
            workspace.gitHubStatuses = [:]
        }
        persistAppSettings()
        syncAutomationServices()
        Task { @MainActor in
            configureUpdater(checkInBackground: settings.autoCheckForUpdates && (!hasConfiguredUpdater || !wasAutoCheckEnabled))
            await refreshAllRepositories(persistAfterEachWorkspace: false)
            persist()
        }
    }

    func updateWorkspaceSettings(workspaceID: UUID, settings: WorkspaceSettings) {
        guard let workspace = workspace(for: workspaceID) else { return }
        workspace.settings = normalizedWorkspaceSettings(settings, for: workspace)
        if workspace.isArchived, !appSettings.showArchivedWorkspaces, selectedWorkspaceID == workspaceID {
            selectedWorkspaceID = sidebarWorkspaces.first(where: { $0.id != workspaceID })?.id
        }
        persist()
    }

    func sidebarIcon(for workspace: WorkspaceModel) -> SidebarItemIcon {
        workspace.workspaceIconOverride ?? (workspace.supportsRepositoryFeatures ? appSettings.defaultRepositoryIcon : appSettings.defaultLocalTerminalIcon)
    }

    func sidebarIcon(for worktree: WorktreeModel, in workspace: WorkspaceModel) -> SidebarItemIcon {
        workspace.iconOverride(for: worktree.path) ?? appSettings.defaultWorktreeIcon
    }

    func sidebarIconRequestTitle(_ request: SidebarIconCustomizationRequest) -> String {
        switch request.target {
        case .workspace(let workspaceID):
            return workspace(for: workspaceID)?.name ?? "Workspace"
        case .worktree(let workspaceID, let worktreePath):
            guard let workspace = workspace(for: workspaceID),
                  let worktree = workspace.worktrees.first(where: { $0.path == worktreePath }) else {
                return URL(fileURLWithPath: worktreePath).lastPathComponent
            }
            return "\(workspace.name) / \(worktree.displayName)"
        case .appDefaultRepository:
            return "Default Repository Icon"
        case .appDefaultLocalTerminal:
            return "Default Terminal Icon"
        case .appDefaultWorktree:
            return "Default Worktree Icon"
        }
    }

    func sidebarIconSelection(for target: SidebarIconCustomizationTarget) -> SidebarItemIcon {
        switch target {
        case .workspace(let workspaceID):
            guard let workspace = workspace(for: workspaceID) else { return appSettings.defaultRepositoryIcon }
            return workspace.workspaceIconOverride ?? sidebarIcon(for: workspace)
        case .worktree(let workspaceID, let worktreePath):
            guard let workspace = workspace(for: workspaceID) else { return appSettings.defaultWorktreeIcon }
            if let override = workspace.iconOverride(for: worktreePath) {
                return override
            }
            guard let worktree = workspace.worktrees.first(where: { $0.path == worktreePath }) else {
                return appSettings.defaultWorktreeIcon
            }
            return sidebarIcon(for: worktree, in: workspace)
        case .appDefaultRepository:
            return appSettings.defaultRepositoryIcon
        case .appDefaultLocalTerminal:
            return appSettings.defaultLocalTerminalIcon
        case .appDefaultWorktree:
            return appSettings.defaultWorktreeIcon
        }
    }

    func updateSidebarIcon(_ icon: SidebarItemIcon, for target: SidebarIconCustomizationTarget) {
        switch target {
        case .workspace(let workspaceID):
            guard let workspace = workspace(for: workspaceID) else { return }
            var settings = workspace.settings
            settings.workspaceIcon = icon
            updateWorkspaceSettings(workspaceID: workspaceID, settings: settings)
        case .worktree(let workspaceID, let worktreePath):
            guard let workspace = workspace(for: workspaceID) else { return }
            var settings = workspace.settings
            settings.worktreeIconOverrides[worktreePath] = icon
            updateWorkspaceSettings(workspaceID: workspaceID, settings: settings)
        case .appDefaultRepository:
            var settings = appSettings
            settings.defaultRepositoryIcon = icon
            appSettings = settings
            persistAppSettings()
        case .appDefaultLocalTerminal:
            var settings = appSettings
            settings.defaultLocalTerminalIcon = icon
            appSettings = settings
            persistAppSettings()
        case .appDefaultWorktree:
            var settings = appSettings
            settings.defaultWorktreeIcon = icon
            appSettings = settings
            persistAppSettings()
        }
    }

    func resetSidebarIcon(for target: SidebarIconCustomizationTarget) {
        switch target {
        case .workspace(let workspaceID):
            guard let workspace = workspace(for: workspaceID) else { return }
            var settings = workspace.settings
            settings.workspaceIcon = nil
            updateWorkspaceSettings(workspaceID: workspaceID, settings: settings)
        case .worktree(let workspaceID, let worktreePath):
            guard let workspace = workspace(for: workspaceID) else { return }
            var settings = workspace.settings
            settings.worktreeIconOverrides[worktreePath] = nil
            updateWorkspaceSettings(workspaceID: workspaceID, settings: settings)
        case .appDefaultRepository:
            var settings = appSettings
            settings.defaultRepositoryIcon = .repositoryDefault
            appSettings = settings
            persistAppSettings()
        case .appDefaultLocalTerminal:
            var settings = appSettings
            settings.defaultLocalTerminalIcon = .localTerminalDefault
            appSettings = settings
            persistAppSettings()
        case .appDefaultWorktree:
            var settings = appSettings
            settings.defaultWorktreeIcon = .worktreeDefault
            appSettings = settings
            persistAppSettings()
        }
    }

    func refreshSelectedWorkspace() {
        guard let workspace = selectedWorkspace else { return }
        refresh(workspace)
    }

    func activateSleepPrevention(_ option: SleepPreventionDurationOption) {
        do {
            try sleepPreventionController.start(option)
            sleepPreventionQuickActionOption = option
        } catch {
            receive(
                .statusMessage(
                    "Unable to start macOS sleep prevention: \(error.localizedDescription)",
                    .warning,
                    deliverSystemNotification: false
                )
            )
        }
    }

    func stopSleepPrevention() {
        sleepPreventionController.stop()
    }

    func performPrimarySleepPreventionAction() {
        if sleepPreventionSession == nil {
            activateSleepPrevention(sleepPreventionQuickActionOption)
        } else {
            stopSleepPrevention()
        }
    }

    func openSelectedWorkspaceInPreferredExternalEditor() {
        guard let workspace = selectedWorkspace else { return }
        openWorkspace(workspace, in: appSettings.preferredExternalEditor)
    }

    func openSelectedWorkspaceInExternalEditor(_ editor: ExternalEditor) {
        guard let workspace = selectedWorkspace else { return }
        setPreferredExternalEditor(editor)
        openWorkspace(workspace, in: editor)
    }

    func updateQuickCommandPresets(_ commands: [QuickCommandPreset]) {
        var settings = appSettings
        settings.quickCommandPresets = QuickCommandCatalog.normalizedCommands(commands)
        settings.quickCommandRecentIDs = QuickCommandCatalog.normalizedRecentCommandIDs(
            settings.quickCommandRecentIDs,
            availableCommands: settings.quickCommandPresets
        )
        appSettings = settings
        persistAppSettings()
    }

    func resetQuickCommandPresetsToDefaults() {
        updateQuickCommandPresets(QuickCommandCatalog.defaultCommands)
    }

    func insertQuickCommand(_ preset: QuickCommandPreset) {
        guard let workspace = selectedWorkspace else {
            receive(.statusMessage("Select a workspace before inserting a quick command.", .warning, deliverSystemNotification: false))
            return
        }

        let targetPaneID = workspace.sessionController.focusedPaneID ?? workspace.paneOrder.first
        guard let targetPaneID,
              let session = workspace.sessionController.session(for: targetPaneID) else {
            receive(.statusMessage("Focus a terminal pane before inserting a quick command.", .warning, deliverSystemNotification: false))
            return
        }

        workspace.sessionController.focus(targetPaneID)
        session.insertText(preset.command)
        recordQuickCommandUse(preset.id)
        receive(
            .statusMessage(
                "Inserted \(preset.normalizedTitle). Press Return to run it.",
                .neutral,
                deliverSystemNotification: false
            )
        )
    }

    func refresh(_ workspace: WorkspaceModel) {
        Task { @MainActor in
            await refreshWorkspace(workspace)
        }
    }

    func refreshWorkspaces(ids: [UUID]) {
        let selectedIDs = Set(ids)
        for workspace in workspaces where selectedIDs.contains(workspace.id) {
            refresh(workspace)
        }
    }

    func refreshWorkspace(_ workspace: WorkspaceModel, persistAfterRefresh: Bool = true) async {
        guard workspace.supportsRepositoryFeatures else {
            workspace.bootstrapIfNeeded()
            objectWillChange.send()
            if persistAfterRefresh {
                persist()
            }
            return
        }
        do {
            let snapshot = try await gitRepositoryService.inspectRepository(at: workspace.activeWorktreePath, repositoryRoot: workspace.repositoryRoot)
            workspace.apply(snapshot: snapshot)
            let statuses = try await gitRepositoryService.repositoryStatuses(for: workspace.worktrees.map(\.path))
            workspace.mergeWorktreeStatuses(statuses)
            workspace.gitHubStatuses = [:]
            workspace.bootstrapIfNeeded()
            configureMetadataWatchers()
            objectWillChange.send()
            if persistAfterRefresh {
                persist()
            }
        } catch {
            presentError(title: "Unable to Refresh Repository", message: error.localizedDescription)
        }
    }

    func fetch(_ workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        Task { @MainActor in
            do {
                try await gitRepositoryService.fetch(for: workspace.repositoryRoot)
                await refreshWorkspace(workspace)
            } catch {
                presentError(title: "git fetch Failed", message: error.localizedDescription)
            }
        }
    }

    func fetchWorkspaces(ids: [UUID]) {
        let selectedIDs = Set(ids)
        for workspace in workspaces where selectedIDs.contains(workspace.id) {
            fetch(workspace)
        }
    }

    func openInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func copyPaths(_ paths: [String]) {
        let normalized = paths.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(normalized.joined(separator: "\n"), forType: .string)
    }

    func moveWorkspaces(withIDs ids: [UUID], toRootIndex destinationIndex: Int) {
        let selectedIDs = Set(ids)
        let moving = workspaces.filter { selectedIDs.contains($0.id) }
        guard !moving.isEmpty else { return }

        let remaining = workspaces.filter { !selectedIDs.contains($0.id) }
        let clampedDestination = min(max(destinationIndex, 0), remaining.count)

        var reordered = remaining
        reordered.insert(contentsOf: moving, at: clampedDestination)
        workspaces = reordered
        persist()
    }

    func createSession(in workspace: WorkspaceModel) {
        workspace.createPane(splitAxis: workspace.layout == nil ? nil : .vertical)
        persist()
    }

    func createSession(
        in workspace: WorkspaceModel,
        backendConfiguration: SessionBackendConfiguration,
        workingDirectory: String
    ) {
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: workingDirectory,
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: backendConfiguration
        )
        workspace.createPane(
            splitAxis: workspace.layout == nil ? nil : .vertical,
            snapshot: snapshot
        )
        persist()
    }

    func createSession(in workspace: WorkspaceModel, for worktree: WorktreeModel) {
        openWorktree(workspace, worktree: worktree, requestedAction: .newSession)
    }

    func duplicateFocusedPane(in workspace: WorkspaceModel) {
        workspace.duplicateFocusedPane()
        persist()
    }

    func splitFocusedPane(in workspace: WorkspaceModel, axis: PaneSplitAxis) {
        workspace.createPane(splitAxis: axis)
        persist()
    }

    func split(in workspace: WorkspaceModel, for worktree: WorktreeModel, axis: PaneSplitAxis) {
        openWorktree(
            workspace,
            worktree: worktree,
            requestedAction: axis == .vertical ? .splitVertical : .splitHorizontal
        )
    }

    func closePane(in workspace: WorkspaceModel, paneID: UUID) {
        workspace.closePane(paneID)
        persist()
    }

    func focusNextPane(in workspace: WorkspaceModel) {
        workspace.sessionController.focusNext(using: workspace.paneOrder)
        persist()
    }

    func focusPreviousPane(in workspace: WorkspaceModel) {
        workspace.sessionController.focusPrevious(using: workspace.paneOrder)
        persist()
    }

    func focusPane(in workspace: WorkspaceModel, direction: PaneFocusDirection) {
        workspace.focusPane(in: direction)
        persist()
    }

    func focusLastPane(in workspace: WorkspaceModel) {
        workspace.focusLastPane()
        persist()
    }

    func restartFocusedSession(in workspace: WorkspaceModel) {
        workspace.sessionController.restartFocused()
    }

    func clearFocusedSession(in workspace: WorkspaceModel) {
        workspace.sessionController.clearFocused()
    }

    func createTab(in workspace: WorkspaceModel) {
        workspace.createTab()
        persist()
    }

    func selectTab(in workspace: WorkspaceModel, tabID: UUID) {
        workspace.selectTab(tabID)
        persist()
    }

    func selectTab(in workspace: WorkspaceModel, index: Int) {
        workspace.selectTab(at: index)
        persist()
    }

    func closeTab(in workspace: WorkspaceModel, tabID: UUID) {
        workspace.closeTab(tabID)
        persist()
    }

    func renameTab(in workspace: WorkspaceModel, tabID: UUID, title: String) {
        workspace.renameTab(tabID, title: title)
        persist()
    }

    func moveTabLeft(in workspace: WorkspaceModel, tabID: UUID) {
        workspace.moveTabLeft(tabID)
        persist()
    }

    func moveTabRight(in workspace: WorkspaceModel, tabID: UUID) {
        workspace.moveTabRight(tabID)
        persist()
    }

    func moveTab(in workspace: WorkspaceModel, tabID: UUID, to index: Int) {
        workspace.moveTab(tabID, to: index)
        persist()
    }

    func selectNextTab(in workspace: WorkspaceModel) {
        workspace.selectNextTab()
        persist()
    }

    func selectPreviousTab(in workspace: WorkspaceModel) {
        workspace.selectPreviousTab()
        persist()
    }

    func equalizeSplits(in workspace: WorkspaceModel) {
        workspace.equalizeLayout()
        persist()
    }

    func toggleZoom(in workspace: WorkspaceModel, paneID: UUID? = nil) {
        workspace.toggleZoom(on: paneID)
        persist()
    }

    func restartAllSessions(in workspace: WorkspaceModel) {
        workspace.restartAllPanes()
        persist()
    }

    func resetLayout(in workspace: WorkspaceModel) {
        workspace.resetLayout()
        persist()
    }

    func presentCreateWorktree(for workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        createWorktreeRequest = CreateWorktreeSheetRequest(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            repositoryRoot: workspace.repositoryRoot
        )
    }

    func presentCreateSSHSession(for workspace: WorkspaceModel) {
        createSSHSessionRequest = CreateSSHSessionRequest(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            defaultWorkingDirectory: workspace.activeWorktreePath
        )
    }

    func presentCreateAgentSession(for workspace: WorkspaceModel) {
        createAgentSessionRequest = CreateAgentSessionRequest(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            defaultWorkingDirectory: workspace.activeWorktreePath,
            presets: workspace.agentPresets,
            preferredPresetID: workspace.preferredAgentPresetID
        )
    }

    func createSSHSession(workspaceID: UUID, draft: CreateSSHSessionDraft) {
        guard let configuration = draft.configuration,
              let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        createSession(
            in: workspace,
            backendConfiguration: .ssh(configuration),
            workingDirectory: workspace.activeWorktreePath
        )
        recordActivity(
            in: workspace,
            kind: .remote,
            title: "Opened SSH session",
            detail: configuration.destination,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .ssh(configuration),
                workingDirectory: workspace.activeWorktreePath
            )
        )
    }

    func createAgentSession(workspaceID: UUID, draft: CreateAgentSessionDraft) {
        guard let configuration = draft.configuration,
              let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        createSession(
            in: workspace,
            backendConfiguration: .agent(configuration),
            workingDirectory: configuration.workingDirectory ?? workspace.activeWorktreePath
        )
        recordActivity(
            in: workspace,
            kind: .agent,
            title: "Opened agent session",
            detail: configuration.name,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(configuration),
                workingDirectory: configuration.workingDirectory ?? workspace.activeWorktreePath
            )
        )
    }

    func createAgentSession(workspaceID: UUID, preset: AgentPreset) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        createSession(
            in: workspace,
            backendConfiguration: .agent(preset.configuration),
            workingDirectory: preset.workingDirectory ?? workspace.activeWorktreePath
        )
        recordActivity(
            in: workspace,
            kind: .agent,
            title: "Launched preset agent",
            detail: preset.name,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(preset.configuration),
                workingDirectory: preset.workingDirectory ?? workspace.activeWorktreePath
            )
        )
    }

    @discardableResult
    func createWorktree(workspaceID: UUID, draft: CreateWorktreeDraft) -> Bool {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }),
              workspace.supportsRepositoryFeatures else { return false }

        let normalizedDirectoryPath = URL(fileURLWithPath: draft.normalizedDirectoryPath)
            .standardizedFileURL
            .path
        let normalizedBranchName = draft.normalizedBranchName

        guard !normalizedDirectoryPath.isEmpty else {
            presentError(title: "Unable to Create Worktree", message: "Directory path is required.")
            return false
        }
        guard !normalizedBranchName.isEmpty else {
            presentError(title: "Unable to Create Worktree", message: "Branch name is required.")
            return false
        }
        guard !normalizedBranchName.contains(" ") else {
            presentError(title: "Unable to Create Worktree", message: "Branch names cannot contain spaces.")
            return false
        }
        guard !FileManager.default.fileExists(atPath: normalizedDirectoryPath) else {
            presentError(title: "Unable to Create Worktree", message: "This path already exists. Please keep adding to the branch name.")
            return false
        }

        let request = CreateWorktreeRequest(
            directoryPath: normalizedDirectoryPath,
            branchName: normalizedBranchName,
            createNewBranch: draft.createNewBranch
        )

        Task { @MainActor in
            do {
                try await gitRepositoryService.createWorktree(rootPath: workspace.repositoryRoot, request: request)
                await refreshWorkspace(workspace)
                objectWillChange.send()
                if let worktree = workspace.worktrees.first(where: {
                    URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedDirectoryPath
                }) {
                    activateWorktree(workspace: workspace, worktree: worktree, restartRunning: false, requestedAction: .none)
                    runSetupScriptIfNeeded(in: workspace)
                }
            } catch {
                presentError(title: "Unable to Create Worktree", message: error.localizedDescription)
            }
        }

        return true
    }

    func requestSwitchToWorktree(_ worktree: WorktreeModel, in workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        openWorktree(workspace, worktree: worktree, requestedAction: .none)
    }

    private func openWorktree(_ workspace: WorkspaceModel, worktree: WorktreeModel, requestedAction: PendingWorktreeAction) {
        guard workspace.activeWorktreePath != worktree.path else {
            perform(requestedAction, in: workspace)
            selectWorkspace(workspace)
            return
        }
        activateWorktree(workspace: workspace, worktree: worktree, restartRunning: false, requestedAction: requestedAction)
    }

    func confirmPendingWorktreeSwitch() {
        guard let pendingWorktreeSwitch else { return }
        self.pendingWorktreeSwitch = nil
        guard
            let workspace = workspaces.first(where: { $0.id == pendingWorktreeSwitch.workspaceID }),
            let worktree = workspace.worktrees.first(where: { $0.path == pendingWorktreeSwitch.targetPath })
        else {
            return
        }
        activateWorktree(
            workspace: workspace,
            worktree: worktree,
            restartRunning: true,
            requestedAction: pendingWorktreeSwitch.requestedAction
        )
    }

    func requestWorktreeRemoval(_ worktree: WorktreeModel, in workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        requestWorktreeRemoval([worktree], in: workspace)
    }

    func requestWorktreeRemoval(_ worktrees: [WorktreeModel], in workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        let uniqueWorktrees = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.path, $0) }).values.sorted { $0.path < $1.path }
        guard !uniqueWorktrees.isEmpty else { return }

        if uniqueWorktrees.contains(where: \.isMainWorktree) {
            presentError(title: "Cannot Remove Main Worktree", message: "The primary repository checkout cannot be removed from the sidebar.")
            return
        }

        let activePaneCount = uniqueWorktrees.reduce(0) { partialResult, worktree in
            partialResult + workspace.activeSessionCount(forWorktreePath: worktree.path)
        }

        let statusesByPath = Dictionary(uniqueKeysWithValues: uniqueWorktrees.map { worktree in
            (worktree.path, workspace.status(for: worktree.path))
        })
        let dirtyWorktrees = uniqueWorktrees.filter { statusesByPath[$0.path]??.hasUncommittedChanges == true }
        let aheadWorktrees = uniqueWorktrees.filter { (statusesByPath[$0.path]??.aheadCount ?? 0) > 0 }

        pendingWorktreeRemoval = PendingWorktreeRemoval(
            workspaceID: workspace.id,
            worktreePaths: uniqueWorktrees.map(\.path),
            worktreeNames: uniqueWorktrees.map(\.displayName),
            activePaneCount: activePaneCount,
            includesActiveWorktree: uniqueWorktrees.contains(where: { workspace.activeWorktreePath == $0.path }),
            dirtyWorktreeNames: dirtyWorktrees.map(\.displayName),
            dirtyFileCount: dirtyWorktrees.reduce(0) { $0 + (statusesByPath[$1.path]??.changedFileCount ?? 0) },
            aheadWorktreeNames: aheadWorktrees.map(\.displayName),
            aheadCommitCount: aheadWorktrees.reduce(0) { $0 + (statusesByPath[$1.path]??.aheadCount ?? 0) }
        )
    }

    func requestWorktreeRemoval(paths: [String], in workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        let worktrees = workspace.worktrees.filter { paths.contains($0.path) }
        requestWorktreeRemoval(worktrees, in: workspace)
    }

    func confirmPendingWorktreeRemoval(force: Bool = false) {
        guard let pendingWorktreeRemoval else { return }
        self.pendingWorktreeRemoval = nil
        guard let workspace = workspaces.first(where: { $0.id == pendingWorktreeRemoval.workspaceID }) else {
            return
        }

        Task { @MainActor in
            do {
                workspace.prepareForWorktreeRemoval(paths: pendingWorktreeRemoval.worktreePaths)
                for path in pendingWorktreeRemoval.worktreePaths {
                    try await gitRepositoryService.removeWorktree(rootPath: workspace.repositoryRoot, path: path, force: force)
                }
                workspace.forgetWorktrees(paths: pendingWorktreeRemoval.worktreePaths)
                await refreshWorkspace(workspace)
            } catch {
                await refreshWorkspace(workspace)
                presentError(title: "Unable to Remove Worktree", message: error.localizedDescription)
            }
        }
    }

    func dispatch(_ command: WorkspaceCommand) {
        switch command {
        case .toggleCommandPalette:
            isCommandPalettePresented.toggle()
            if isCommandPalettePresented {
                syncCommandPaletteSelection()
            } else {
                resetCommandPalette()
            }

        case .toggleOverview:
            dismissCommandPalette()
            isOverviewPresented.toggle()

        case .presentSettings:
            dismissCommandPalette()
            presentSettings(for: selectedWorkspace)

        case .checkForUpdates:
            dismissCommandPalette()
            checkForUpdates()

        case .openLatestRelease:
            dismissCommandPalette()
            openLatestRelease()

        case .dismissTransientUI:
            resetCommandPalette()
            settingsRequest = nil
            isOverviewPresented = false

        case .selectWorkspace(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                selectWorkspace(workspace)
            }

        case .refreshWorkspace(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                refresh(workspace)
            }

        case .refreshAllRepositories:
            dismissCommandPalette()
            Task { @MainActor in
                await refreshAllRepositories()
            }

        case .createSession(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                createSession(in: workspace)
            }

        case .splitFocusedPane(let id, let axis):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                splitFocusedPane(in: workspace, axis: axis)
            }

        case .createWorktree(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                presentCreateWorktree(for: workspace)
            }

        case .createSSHSession(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                presentCreateSSHSession(for: workspace)
            }

        case .createAgentSession(let id, let preset):
            dismissCommandPalette()
            if let preset {
                createAgentSession(workspaceID: id, preset: preset)
            } else if let workspace = workspace(for: id) {
                presentCreateAgentSession(for: workspace)
            }

        case .openRemoteTargetShell(let workspaceID, let targetID):
            dismissCommandPalette()
            openRemoteTargetShell(workspaceID: workspaceID, targetID: targetID)

        case .openRemoteTargetAgent(let workspaceID, let targetID):
            dismissCommandPalette()
            openRemoteTargetAgent(workspaceID: workspaceID, targetID: targetID)

        case .runWorkspaceScript(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                runWorkspaceScript(in: workspace)
            }

        case .runSetupScript(let id):
            dismissCommandPalette()
            if let workspace = workspace(for: id) {
                runSetupScriptIfNeeded(in: workspace)
            }

        case .runWorkflow(let id, let workflowID):
            dismissCommandPalette()
            if let workspace = workspace(for: id),
               let workflow = workspace.workflows.first(where: { $0.id == workflowID }) {
                runWorkflow(workflow, in: workspace)
            }

        case .toggleWorkspacePinned(let id):
            if let workspace = workspace(for: id) {
                workspace.isPinned.toggle()
                persist()
            }

        case .toggleWorkspaceArchived(let id):
            if let workspace = workspace(for: id) {
                workspace.isArchived.toggle()
                if workspace.isArchived, selectedWorkspaceID == id, !appSettings.showArchivedWorkspaces {
                    selectedWorkspaceID = sidebarWorkspaces.first(where: { $0.id != id })?.id
                }
                persist()
            }

        case .toggleShowArchived:
            appSettings.showArchivedWorkspaces.toggle()
            if !appSettings.showArchivedWorkspaces,
               let selectedWorkspace,
               selectedWorkspace.isArchived {
                selectedWorkspaceID = sidebarWorkspaces.first(where: { !$0.isArchived })?.id
            }
            persistAppSettings()

        case .openPullRequest(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await openPullRequest(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .markPullRequestReady(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await markPullRequestReady(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .updatePullRequestBranch(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await updatePullRequestBranch(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .queuePullRequest(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await queuePullRequest(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .copyPullRequestReleaseNotes(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await copyPullRequestReleaseNotes(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .updatePullRequestBranches(let targets):
            dismissCommandPalette()
            Task { @MainActor in
                await updatePullRequestBranches(targets)
            }

        case .queuePullRequests(let targets):
            dismissCommandPalette()
            Task { @MainActor in
                await queuePullRequests(targets)
            }

        case .copyPullRequestReleaseNotesBatch(let targets):
            dismissCommandPalette()
            Task { @MainActor in
                await copyPullRequestReleaseNotesBatch(targets)
            }

        case .openLatestRun(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await openLatestRun(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .openFailingCheckDetails(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await openFailingCheckDetails(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .copyFailingCheckURL(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await copyFailingCheckURL(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .rerunLatestFailedJobs(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await rerunLatestFailedJobs(workspaceID: workspaceID, worktreePath: worktreePath)
            }

        case .copyLatestRunLogs(let workspaceID, let worktreePath):
            dismissCommandPalette()
            Task { @MainActor in
                await copyLatestRunLogs(workspaceID: workspaceID, worktreePath: worktreePath)
            }
        }
    }

    func receive(_ event: WorkspaceEvent) {
        switch event {
        case .autoRefreshTick:
            Task { @MainActor in
                await refreshAllRepositories(persistAfterEachWorkspace: false)
                persist()
            }
        case .workspaceWatchTriggered(let workspaceID):
            guard let workspace = workspace(for: workspaceID) else { return }
            Task { @MainActor in
                await refreshWorkspace(workspace)
            }
        case .gitHubIntegrationStateUpdated:
            gitHubIntegrationState = .disabled
        case .statusMessage(let text, let tone, let deliverSystemNotification):
            statusMessageTask?.cancel()
            statusMessage = WorkspaceStatusMessage(text: text, tone: tone)
            if deliverSystemNotification && appSettings.systemNotificationsEnabled {
                WorkspaceNotificationCenter.shared.deliver(title: "Liney", body: text)
            }
            statusMessageTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                if self.statusMessage?.text == text {
                    self.statusMessage = nil
                }
            }
        }
    }

    func updateCommandPaletteQuery(_ query: String) {
        commandPaletteQuery = query
        syncCommandPaletteSelection()
    }

    func moveCommandPaletteSelection(delta: Int) {
        let items = commandPaletteItems
        guard !items.isEmpty else {
            selectedCommandPaletteItemID = nil
            return
        }

        let currentIndex = items.firstIndex { $0.id == selectedCommandPaletteItemID } ?? 0
        let nextIndex = (currentIndex + delta + items.count) % items.count
        selectedCommandPaletteItemID = items[nextIndex].id
    }

    func activateSelectedCommandPaletteItem() {
        guard let item = commandPaletteItems.first(where: { $0.id == selectedCommandPaletteItemID }) else { return }
        recordCommandPaletteActivation(itemID: item.id)
        dispatch(command(for: item))
    }

    func persist() {
        do {
            let prunedGlobalCanvasState = globalCanvasState.pruned(to: validGlobalCanvasCardIDs())
            if prunedGlobalCanvasState != globalCanvasState {
                globalCanvasState = prunedGlobalCanvasState
            }
            if persistsWorkspaceState {
                try persistence.save(
                    PersistedWorkspaceState(
                        selectedWorkspaceID: selectedWorkspaceID,
                        workspaces: workspaces.map { $0.snapshot() },
                        globalCanvasState: prunedGlobalCanvasState
                    )
                )
            }
            persistAppSettings()
        } catch {
            presentedError = PresentedError(title: "Unable to Save State", message: error.localizedDescription)
        }
    }

    func currentStateSnapshot() -> PersistedWorkspaceState {
        PersistedWorkspaceState(
            selectedWorkspaceID: selectedWorkspaceID,
            workspaces: workspaces.map { $0.snapshot() },
            globalCanvasState: globalCanvasState.pruned(to: validGlobalCanvasCardIDs())
        )
    }

    func setWorkspaceStatePersistenceEnabled(_ enabled: Bool) {
        persistsWorkspaceState = enabled
    }

    func replayActivity(workspaceID: UUID, activityID: UUID) {
        guard let workspace = workspace(for: workspaceID),
              let entry = workspace.activityLog.first(where: { $0.id == activityID }) else {
            return
        }
        replayActivity(entry, in: workspace)
    }

    func clearTimeline() {
        let hadActivity = workspaces.contains { !$0.activityLog.isEmpty }
        guard hadActivity else { return }
        for workspace in workspaces where !workspace.activityLog.isEmpty {
            workspace.clearActivityLog()
        }
        persist()
        receive(.statusMessage("Cleared task timeline.", .neutral, deliverSystemNotification: false))
    }

    private func command(for item: CommandPaletteItem) -> WorkspaceCommand {
        switch item.kind {
        case .command(let command):
            return command
        }
    }

    private func dismissCommandPalette() {
        isCommandPalettePresented = false
        resetCommandPalette()
    }

    private func resetCommandPalette() {
        commandPaletteQuery = ""
        selectedCommandPaletteItemID = nil
    }

    private func syncCommandPaletteSelection() {
        let visibleIDs = Set(commandPaletteItems.map(\.id))
        if let selectedCommandPaletteItemID, visibleIDs.contains(selectedCommandPaletteItemID) {
            return
        }
        selectedCommandPaletteItemID = commandPaletteItems.first?.id
    }

    private func recordCommandPaletteActivation(itemID: String) {
        appSettings.commandPaletteRecents[itemID] = Date().timeIntervalSince1970
        persistAppSettings()
    }

    private func handleSleepPreventionEvent(_ event: SleepPreventionControllerEvent) {
        switch event {
        case .started(let session):
            sleepPreventionSession = session
            sleepPreventionReferenceDate = Date()
            startSleepPreventionTicker()
            receive(
                .statusMessage(
                    session.option == .forever
                        ? "macOS sleep prevention is active until you stop it."
                        : "macOS sleep prevention is active for \(session.option.title.lowercased()).",
                    .success,
                    deliverSystemNotification: false
                )
            )

        case .stopped(let reason):
            let previousSession = sleepPreventionSession
            sleepPreventionSession = nil
            sleepPreventionReferenceDate = Date()
            stopSleepPreventionTicker()

            switch reason {
            case .userInitiated:
                receive(.statusMessage("macOS sleep prevention stopped.", .neutral, deliverSystemNotification: false))
            case .completed:
                guard previousSession != nil else { return }
                receive(.statusMessage("macOS sleep prevention finished.", .neutral, deliverSystemNotification: false))
            case .failed(let message):
                receive(.statusMessage(message, .warning, deliverSystemNotification: false))
            }
        }
    }

    private func startSleepPreventionTicker() {
        sleepPreventionTickerTask?.cancel()
        sleepPreventionTickerTask = Task { @MainActor in
            while !Task.isCancelled {
                sleepPreventionReferenceDate = Date()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func stopSleepPreventionTicker() {
        sleepPreventionTickerTask?.cancel()
        sleepPreventionTickerTask = nil
    }

    private func setPreferredExternalEditor(_ editor: ExternalEditor) {
        guard appSettings.preferredExternalEditor != editor else { return }
        var settings = appSettings
        settings.preferredExternalEditor = editor
        appSettings = settings
        persistAppSettings()
    }

    private func recordQuickCommandUse(_ id: String) {
        var recentIDs = appSettings.quickCommandRecentIDs
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)

        var settings = appSettings
        settings.quickCommandRecentIDs = QuickCommandCatalog.normalizedRecentCommandIDs(
            recentIDs,
            availableCommands: settings.quickCommandPresets
        )
        appSettings = settings
        persistAppSettings()
    }

    private func openWorkspace(_ workspace: WorkspaceModel, in preferredEditor: ExternalEditor) {
        let availableEditors = availableExternalEditors
        guard let editor = ExternalEditorCatalog.effectiveEditor(
            preferred: preferredEditor,
            among: availableEditors
        ) else {
            receive(
                .statusMessage(
                    "Install Cursor, Zed, VS Code, Windsurf, Xcode, Fleet, Nova, or Sublime Text to open workspaces from the toolbar.",
                    .warning,
                    deliverSystemNotification: false
                )
            )
            return
        }

        if editor.editor != preferredEditor {
            receive(
                .statusMessage(
                    "\(preferredEditor.displayName) is not installed. Opening in \(editor.editor.displayName) instead.",
                    .warning,
                    deliverSystemNotification: false
                )
            )
        }

        let workspaceName = workspace.name
        let directoryURL = URL(fileURLWithPath: workspace.activeWorktreePath, isDirectory: true)
        ExternalEditorCatalog.open(directoryURL, in: editor) { [weak self] result in
            guard let self else { return }
            guard case .failure(let error) = result else { return }
            self.receive(
                .statusMessage(
                    "Unable to open \(workspaceName) in \(editor.editor.displayName): \(error.localizedDescription)",
                    .warning,
                    deliverSystemNotification: false
                )
            )
        }
    }

    private func activateWorktree(
        workspace: WorkspaceModel,
        worktree: WorktreeModel,
        restartRunning: Bool,
        requestedAction: PendingWorktreeAction
    ) {
        workspace.switchToWorktree(path: worktree.path, restartRunning: restartRunning)
        perform(requestedAction, in: workspace)
        Task { @MainActor in
            await refreshWorkspace(workspace)
        }
        persist()
    }

    private func perform(_ action: PendingWorktreeAction, in workspace: WorkspaceModel) {
        switch action {
        case .none:
            break
        case .newSession:
            workspace.createPane(splitAxis: workspace.layout == nil ? nil : .vertical)
        case .splitVertical:
            workspace.createPane(splitAxis: .vertical)
        case .splitHorizontal:
            workspace.createPane(splitAxis: .horizontal)
        }
    }

    private func presentError(title: String, message: String) {
        presentedError = PresentedError(title: title, message: message)
        receive(.statusMessage(message, .warning, deliverSystemNotification: false))
    }

    private func persistAppSettings() {
        do {
            try appSettingsPersistence.save(appSettings)
            NotificationCenter.default.post(name: .lineyAppSettingsDidChange, object: appSettings)
        } catch {
            presentedError = PresentedError(title: "Unable to Save Settings", message: error.localizedDescription)
        }
    }

    private func workspace(for id: UUID) -> WorkspaceModel? {
        workspaces.first(where: { $0.id == id })
    }

    private func normalizedWorkspaceSettings(
        _ settings: WorkspaceSettings,
        for workspace: WorkspaceModel
    ) -> WorkspaceSettings {
        var normalized = settings

        if normalized.agentPresets.isEmpty {
            normalized.agentPresets = [.codex]
        }

        let validPresetIDs = Set(normalized.agentPresets.map(\.id))
        if let preferredAgentPresetID = normalized.preferredAgentPresetID,
           !validPresetIDs.contains(preferredAgentPresetID) {
            normalized.preferredAgentPresetID = normalized.agentPresets.first?.id
        } else if normalized.preferredAgentPresetID == nil {
            normalized.preferredAgentPresetID = normalized.agentPresets.first?.id
        }

        normalized.remoteTargets = normalized.remoteTargets.map { target in
            var updated = target
            if let agentPresetID = target.agentPresetID, !validPresetIDs.contains(agentPresetID) {
                updated.agentPresetID = nil
            }
            return updated
        }

        normalized.workflows = normalized.workflows.map { workflow in
            var updated = workflow
            if let agentPresetID = workflow.agentPresetID, !validPresetIDs.contains(agentPresetID) {
                updated.agentPresetID = nil
                updated.agentMode = .none
            }
            return updated
        }

        let validWorkflowIDs = Set(normalized.workflows.map(\.id))
        if let preferredWorkflowID = normalized.preferredWorkflowID,
           !validWorkflowIDs.contains(preferredWorkflowID) {
            normalized.preferredWorkflowID = normalized.workflows.first?.id
        } else if normalized.preferredWorkflowID == nil {
            normalized.preferredWorkflowID = normalized.workflows.first?.id
        }

        let validWorktreePaths = Set(workspace.worktrees.map(\.path))
        normalized.worktreeIconOverrides = normalized.worktreeIconOverrides.filter { validWorktreePaths.contains($0.key) }
        return normalized
    }

    private func refreshAllRepositories(persistAfterEachWorkspace: Bool = true) async {
        for workspace in workspaces where workspace.supportsRepositoryFeatures {
            await refreshWorkspace(workspace, persistAfterRefresh: persistAfterEachWorkspace)
        }
    }

    private func syncAutomationServices() {
        startAutoRefreshLoop()
        configureMetadataWatchers()
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        guard appSettings.autoRefreshEnabled else { return }
        let interval = UInt64(max(10, appSettings.autoRefreshIntervalSeconds)) * 1_000_000_000
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                self.receive(.autoRefreshTick)
            }
        }
    }

    private func configureMetadataWatchers() {
        let callback: @Sendable (UUID) -> Void = { [store = self] workspaceID in
            Task { @MainActor in
                store.receive(.workspaceWatchTriggered(workspaceID))
            }
        }
        metadataWatchService.configure(
            workspaces: workspaces.filter(\.supportsRepositoryFeatures),
            isEnabled: appSettings.fileWatcherEnabled,
            onChange: callback
        )
    }

    private func refreshGitHubIntegrationState() async {
        receive(.gitHubIntegrationStateUpdated(.disabled))
    }

    private func configureUpdater(checkInBackground: Bool) {
        updaterController.configure(
            updateChannel: appSettings.releaseChannel,
            automaticallyChecks: appSettings.autoCheckForUpdates,
            automaticallyDownloads: appSettings.autoDownloadUpdates,
            checkInBackground: checkInBackground
        )
        hasConfiguredUpdater = true
    }

    private func refreshGitHubStatus(for workspace: WorkspaceModel) async {
        workspace.gitHubStatuses = [:]
        receive(.gitHubIntegrationStateUpdated(.disabled))
    }

    private func openPullRequest(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Opening pull requests")
    }

    private func markPullRequestReady(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Marking pull requests ready")
    }

    private func updatePullRequestBranch(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Updating pull request branches")
    }

    private func queuePullRequest(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Queueing pull requests")
    }

    private func updatePullRequestBranches(_ targets: [WorkspaceGitHubTarget]) async {
        _ = targets
        notifyGitHubFeatureRemoval("Batch pull request updates")
    }

    private func queuePullRequests(_ targets: [WorkspaceGitHubTarget]) async {
        _ = targets
        notifyGitHubFeatureRemoval("Batch pull request queueing")
    }

    private func copyPullRequestReleaseNotes(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Release note drafting")
    }

    private func copyPullRequestReleaseNotesBatch(_ targets: [WorkspaceGitHubTarget]) async {
        _ = targets
        notifyGitHubFeatureRemoval("Batch release note drafting")
    }

    private func openLatestRun(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Opening CI runs")
    }

    private func openFailingCheckDetails(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Opening failing checks")
    }

    private func copyFailingCheckURL(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Copying failing check URLs")
    }

    private func rerunLatestFailedJobs(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Rerunning CI jobs")
    }

    private func copyLatestRunLogs(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval("Copying CI logs")
    }

    private func openLatestRelease() {
        NSWorkspace.shared.open(AppUpdaterController.releasesURL)
        receive(.statusMessage("Opened Liney release notes.", .neutral, deliverSystemNotification: false))
    }

    private func checkForUpdates() {
        configureUpdater(checkInBackground: false)
        updaterController.checkForUpdates()
        receive(.statusMessage("Checking for updates…", .neutral, deliverSystemNotification: false))
    }

    private func openRemoteTargetShell(workspaceID: UUID, targetID: UUID) {
        guard let workspace = workspace(for: workspaceID) else { return }
        do {
            let plan = try remoteSessionCoordinator.shellPlan(workspace: workspace, targetID: targetID)
            createSession(in: workspace, backendConfiguration: plan.backendConfiguration, workingDirectory: plan.workingDirectory)
            recordActivity(
                in: workspace,
                kind: plan.activityKind,
                title: plan.activityTitle,
                detail: plan.activityDetail,
                worktreePath: workspace.activeWorktreePath,
                replayAction: plan.replayAction
            )
        } catch {
            receive(.statusMessage(error.localizedDescription, .warning, deliverSystemNotification: false))
        }
    }

    private func openRemoteTargetAgent(workspaceID: UUID, targetID: UUID) {
        guard let workspace = workspace(for: workspaceID) else { return }
        do {
            let plan = try remoteSessionCoordinator.agentPlan(workspace: workspace, targetID: targetID)
            createSession(in: workspace, backendConfiguration: plan.backendConfiguration, workingDirectory: plan.workingDirectory)
            recordActivity(
                in: workspace,
                kind: plan.activityKind,
                title: plan.activityTitle,
                detail: plan.activityDetail,
                worktreePath: workspace.activeWorktreePath,
                replayAction: plan.replayAction
            )
        } catch {
            receive(.statusMessage(error.localizedDescription, .warning, deliverSystemNotification: false))
        }
    }

    private func runWorkspaceScript(in workspace: WorkspaceModel) {
        let script = workspace.runScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            receive(.statusMessage("No run script configured for this workspace.", .warning, deliverSystemNotification: false))
            return
        }
        selectWorkspace(workspace)
        if let session = localShellSession(in: workspace, mode: .reuseFocused) {
            session.sendShellCommand(script)
            recordActivity(
                in: workspace,
                kind: .command,
                title: "Ran workspace script",
                detail: summarizeCommand(script),
                worktreePath: workspace.activeWorktreePath,
                replayAction: WorkspaceReplayAction(
                    kind: .runWorkspaceScript,
                    workflowID: nil,
                    worktreePath: nil,
                    backendConfiguration: nil,
                    workingDirectory: nil
                )
            )
            receive(.statusMessage("Sent run script to the focused session.", .success, deliverSystemNotification: false))
        }
    }

    private func runSetupScriptIfNeeded(in workspace: WorkspaceModel) {
        let script = workspace.setupScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return }
        if let session = localShellSession(in: workspace, mode: .reuseFocused) {
            session.sendShellCommand(script)
            recordActivity(
                in: workspace,
                kind: .command,
                title: "Ran setup script",
                detail: summarizeCommand(script),
                worktreePath: workspace.activeWorktreePath,
                replayAction: WorkspaceReplayAction(
                    kind: .runSetupScript,
                    workflowID: nil,
                    worktreePath: nil,
                    backendConfiguration: nil,
                    workingDirectory: nil
                )
            )
            receive(.statusMessage("Ran workspace setup script.", .success, deliverSystemNotification: false))
        }
    }

    private func runWorkflow(_ workflow: WorkspaceWorkflow, in workspace: WorkspaceModel) {
        selectWorkspace(workspace)

        if workflow.runSetupScript || workflow.runWorkspaceScript || workflow.localSessionMode != .reuseFocused {
            guard let session = localShellSession(in: workspace, mode: workflow.localSessionMode) else {
                receive(.statusMessage("Unable to prepare a local shell session for the workflow.", .warning, deliverSystemNotification: false))
                return
            }
            if workflow.runSetupScript {
                let setupScript = workspace.setupScript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !setupScript.isEmpty {
                    session.sendShellCommand(setupScript)
                }
            }
            if workflow.runWorkspaceScript {
                let runScript = workspace.runScript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !runScript.isEmpty {
                    session.sendShellCommand(runScript)
                }
            }
        }

        if let presetID = workflow.agentPresetID,
           let preset = workspace.agentPresets.first(where: { $0.id == presetID }),
           workflow.agentMode != .none {
            launchWorkflowAgent(using: preset, mode: workflow.agentMode, in: workspace)
        }

        recordActivity(
            in: workspace,
            kind: .workflow,
            title: "Ran workflow",
            detail: workflow.name,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .runWorkflow(workflow.id)
        )
        receive(.statusMessage("Ran workflow \(workflow.name).", .success, deliverSystemNotification: false))
    }

    private func localShellSession(in workspace: WorkspaceModel, mode: WorkspaceWorkflowLocalSessionMode) -> ShellSession? {
        if mode == .reuseFocused,
           let focusedPaneID = workspace.sessionController.focusedPaneID,
           let focused = workspace.sessionController.session(for: focusedPaneID),
           focused.backendConfiguration.kind == .localShell {
            return focused
        }

        if mode == .reuseFocused,
           let existing = workspace.paneOrder
            .compactMap({ workspace.sessionController.session(for: $0) })
            .first(where: { $0.backendConfiguration.kind == .localShell }) {
            workspace.sessionController.focus(existing.id)
            return existing
        }

        let splitAxis: PaneSplitAxis? = {
            switch mode {
            case .reuseFocused, .newSession:
                return workspace.layout == nil ? nil : .vertical
            case .splitRight:
                return .vertical
            case .splitDown:
                return .horizontal
            }
        }()

        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: workspace.activeWorktreePath,
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local()
        )
        workspace.createPane(splitAxis: splitAxis, snapshot: snapshot)
        persist()
        return workspace.sessionController.session(for: workspace.sessionController.focusedPaneID ?? snapshot.id)
    }

    private func launchWorkflowAgent(using preset: AgentPreset, mode: WorkspaceWorkflowAgentMode, in workspace: WorkspaceModel) {
        let splitAxis: PaneSplitAxis? = {
            switch mode {
            case .none:
                return nil
            case .newSession:
                return workspace.layout == nil ? nil : .vertical
            case .splitRight:
                return .vertical
            case .splitDown:
                return .horizontal
            }
        }()

        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: preset.workingDirectory ?? workspace.activeWorktreePath,
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .agent(preset.configuration)
        )
        workspace.createPane(splitAxis: splitAxis, snapshot: snapshot)
        recordActivity(
            in: workspace,
            kind: .agent,
            title: "Launched workflow agent",
            detail: preset.name,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(preset.configuration),
                workingDirectory: preset.workingDirectory ?? workspace.activeWorktreePath
            )
        )
        persist()
    }

    private func replayActivity(_ entry: WorkspaceActivityEntry, in workspace: WorkspaceModel) {
        guard let action = entry.replayAction else {
            receive(.statusMessage("This activity cannot be replayed yet.", .neutral, deliverSystemNotification: false))
            return
        }

        selectWorkspace(workspace)

        switch action.kind {
        case .runWorkspaceScript:
            runWorkspaceScript(in: workspace)
        case .runSetupScript:
            runSetupScriptIfNeeded(in: workspace)
        case .runWorkflow:
            guard let workflowID = action.workflowID,
                  let workflow = workspace.workflows.first(where: { $0.id == workflowID }) else {
                receive(.statusMessage("The saved workflow is no longer available.", .warning, deliverSystemNotification: false))
                return
            }
            runWorkflow(workflow, in: workspace)
        case .createSession:
            guard let backendConfiguration = action.backendConfiguration else {
                receive(.statusMessage("The saved session configuration is incomplete.", .warning, deliverSystemNotification: false))
                return
            }
            createSession(
                in: workspace,
                backendConfiguration: backendConfiguration,
                workingDirectory: action.workingDirectory ?? workspace.activeWorktreePath
            )
            receive(.statusMessage("Replayed \(entry.title.lowercased()).", .success, deliverSystemNotification: false))
        case .openPullRequest:
            notifyGitHubFeatureRemoval("Opening pull requests")
        case .markPullRequestReady:
            notifyGitHubFeatureRemoval("Marking pull requests ready")
        case .openLatestRun:
            notifyGitHubFeatureRemoval("Opening CI runs")
        }
    }

    private func recordActivity(
        in workspace: WorkspaceModel,
        kind: WorkspaceActivityKind,
        title: String,
        detail: String,
        worktreePath: String? = nil,
        replayAction: WorkspaceReplayAction? = nil
    ) {
        workspace.recordActivity(
            WorkspaceActivityEntry(
                kind: kind,
                title: title,
                detail: detail,
                worktreePath: worktreePath,
                replayAction: replayAction
            ),
            limit: activityLogLimit
        )
        persist()
    }

    private func applyStatusUpdate(_ update: WorkspaceCoordinatorStatusUpdate?) {
        guard let update else { return }
        receive(.statusMessage(update.text, update.tone, deliverSystemNotification: false))
    }

    private func applyCoordinatorEffects(_ effects: [WorkspaceCoordinatorEffect]) {
        for effect in effects {
            switch effect {
            case .openURL(let url):
                NSWorkspace.shared.open(url)
            case .copyText(let text):
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    private func applyCoordinatorActivities(_ activities: [WorkspaceCoordinatorActivityRecord]) {
        for activity in activities {
            guard let workspace = workspace(for: activity.workspaceID) else { continue }
            recordActivity(
                in: workspace,
                kind: activity.kind,
                title: activity.title,
                detail: activity.detail,
                worktreePath: activity.worktreePath,
                replayAction: activity.replayAction
            )
        }
    }

    private func notifyGitHubFeatureRemoval(_ action: String) {
        receive(
            .statusMessage(
                "\(action) is no longer available because GitHub integration has been removed from Liney.",
                .warning,
                deliverSystemNotification: false
            )
        )
    }

    private func summarizeCommand(_ script: String) -> String {
        let compact = script
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? script.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 72 {
            return compact
        }
        return String(compact.prefix(72)) + "..."
    }

    private func normalizeLaunchState(_ state: PersistedWorkspaceState) -> PersistedWorkspaceState {
        guard !state.workspaces.isEmpty else { return state }

        var normalized = state
        let selectedWorkspaceID = state.selectedWorkspaceID ?? state.workspaces.first?.id
        let targetIndex = normalized.workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) ?? 0
        var workspace = normalized.workspaces[targetIndex]
        let activePath = workspace.activeWorktreePath
        let currentState = workspace.worktreeStates.first(where: { $0.worktreePath == activePath })
            ?? WorktreeSessionStateRecord.makeDefault(for: activePath)

        let preservedPane: PaneSnapshot
        if let focusedPaneID = currentState.focusedPaneID,
           let focusedPane = currentState.panes.first(where: { $0.id == focusedPaneID }) {
            preservedPane = focusedPane
        } else if let firstPane = currentState.panes.first {
            preservedPane = firstPane
        } else {
            preservedPane = PaneSnapshot.makeDefault(cwd: activePath)
        }

        let startupState = WorktreeSessionStateRecord(
            worktreePath: activePath,
            layout: .pane(PaneLeaf(paneID: preservedPane.id)),
            panes: [preservedPane],
            focusedPaneID: preservedPane.id,
            zoomedPaneID: nil
        )

        if let stateIndex = workspace.worktreeStates.firstIndex(where: { $0.worktreePath == activePath }) {
            workspace.worktreeStates[stateIndex] = startupState
        } else {
            workspace.worktreeStates.append(startupState)
        }

        normalized.workspaces[targetIndex] = workspace
        normalized.globalCanvasState = normalized.globalCanvasState.pruned(
            to: validGlobalCanvasCardIDs(in: normalized.workspaces)
        )
        return normalized
    }

    private func ensureDefaultWorkspace() {
        guard workspaces.isEmpty else { return }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let workspace = WorkspaceModel(localDirectoryPath: homePath)
        workspaces = [workspace]
        selectedWorkspaceID = workspace.id
    }

    private func removeDefaultLocalWorkspaceIfNeeded() {
        guard workspaces.count > 1 else { return }
        let localWorkspaces = workspaces.filter { !$0.supportsRepositoryFeatures }
        guard localWorkspaces.count == 1, let localWorkspace = localWorkspaces.first else { return }
        workspaces.removeAll { $0.id == localWorkspace.id }
        if selectedWorkspaceID == localWorkspace.id {
            selectedWorkspaceID = workspaces.first?.id
        }
    }

    private func validGlobalCanvasCardIDs() -> Set<GlobalCanvasCardID> {
        validGlobalCanvasCardIDs(in: workspaces.map { $0.snapshot() })
    }

    private func validGlobalCanvasCardIDs(in workspaces: [WorkspaceModel]) -> Set<GlobalCanvasCardID> {
        validGlobalCanvasCardIDs(in: workspaces.map { $0.snapshot() })
    }

    private func validGlobalCanvasCardIDs(in workspaces: [WorkspaceRecord]) -> Set<GlobalCanvasCardID> {
        Set(
            workspaces.flatMap { workspace in
                workspace.worktreeStates.flatMap { state in
                    state.tabs.map { tab in
                        GlobalCanvasCardID(
                            workspaceID: workspace.id,
                            worktreePath: state.worktreePath,
                            tabID: tab.id
                        )
                    }
                }
            }
        )
    }
}
