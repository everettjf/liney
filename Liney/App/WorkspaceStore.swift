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
    @Published private(set) var hapiIntegrationState: HAPIIntegrationState = .unavailable

    private let persistence = WorkspaceStatePersistence()
    private let appSettingsPersistence = AppSettingsPersistence()
    private let initialWorkspaceState: PersistedWorkspaceState?
    private let initialAppSettings: AppSettings?
    private let gitRepositoryService = GitRepositoryService()
    private let updaterController = AppUpdaterController.shared
    private let remoteSessionCoordinator = RemoteSessionCoordinator()
    private let metadataWatchService = WorkspaceMetadataWatchService.shared
    private let sleepPreventionController = SleepPreventionController()
    private var persistsWorkspaceState: Bool
    private var hasLoaded = false
    private var hasConfiguredUpdater = false
    private var autoRefreshTask: Task<Void, Never>?
    private var statusMessageTask: Task<Void, Never>?
    private var sleepPreventionTickerTask: Task<Void, Never>?

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

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

    deinit {
        autoRefreshTask?.cancel()
        statusMessageTask?.cancel()
        sleepPreventionTickerTask?.cancel()
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated {
            metadataWatchService.stop()
            sleepPreventionController.onEvent = nil
            sleepPreventionController.stop()
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

    var availableHAPIInstallation: HAPIInstallationStatus? {
        guard case .available(let installation) = hapiIntegrationState else {
            return nil
        }
        return installation
    }

    var quickCommandPresets: [QuickCommandPreset] {
        appSettings.quickCommandPresets
    }

    var quickCommandCategories: [QuickCommandCategory] {
        appSettings.quickCommandCategories
    }

    var agentPresets: [AgentPreset] {
        appSettings.agentPresets
    }

    var preferredAgentPreset: AgentPreset? {
        if let preferredAgentPresetID = appSettings.preferredAgentPresetID,
           let preset = appSettings.agentPresets.first(where: { $0.id == preferredAgentPresetID }) {
            return preset
        }
        return appSettings.agentPresets.first
    }

    var quickCommandCategoryMap: [String: QuickCommandCategory] {
        QuickCommandCatalog.categoryMap(quickCommandCategories)
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
            return localized("main.sleepPrevention.status")
        }
        return localizedFormat(
            "main.sleepPrevention.statusActiveFormat",
            sleepPreventionSession.remainingDescription(relativeTo: sleepPreventionReferenceDate)
        )
    }

    var sleepPreventionPrimaryActionLabel: String {
        sleepPreventionSession == nil ? localized("main.sleepPrevention.start") : localized("main.sleepPrevention.stop")
    }

    var sleepPreventionPrimaryActionHelpText: String {
        if let sleepPreventionSession {
            return localizedFormat(
                "main.sleepPrevention.helpStopFormat",
                sleepPreventionSession.remainingDescription(relativeTo: sleepPreventionReferenceDate)
            )
        }
        return localizedFormat("main.sleepPrevention.helpStartFormat", sleepPreventionQuickActionOption.title)
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
                title: isOverviewPresented ? localized("main.commandPalette.overview.close") : localized("main.commandPalette.overview.open"),
                subtitle: localizedFormat("main.commandPalette.workspacesCountFormat", workspaces.count),
                group: .navigation,
                keywords: ["overview", "dashboard", "summary"],
                isGlobal: true,
                kind: .command(.toggleOverview)
            ),
            CommandPaletteItem(
                id: "settings",
                title: localized("main.commandPalette.openSettings"),
                subtitle: nil,
                group: .navigation,
                keywords: ["preferences", "configuration"],
                isGlobal: true,
                kind: .command(.presentSettings)
            ),
            CommandPaletteItem(
                id: "refresh-all",
                title: localized("main.commandPalette.refreshAllRepositories"),
                subtitle: nil,
                group: .automation,
                keywords: ["reload", "sync", "repositories"],
                isGlobal: true,
                kind: .command(.refreshAllRepositories)
            ),
            CommandPaletteItem(
                id: "toggle-archived",
                title: appSettings.showArchivedWorkspaces ? localized("main.commandPalette.hideArchivedWorkspaces") : localized("main.commandPalette.showArchivedWorkspaces"),
                subtitle: nil,
                group: .navigation,
                keywords: ["archive", "sidebar"],
                isGlobal: true,
                kind: .command(.toggleShowArchived)
            ),
            CommandPaletteItem(
                id: "check-updates",
                title: localized("main.commandPalette.checkForUpdates"),
                subtitle: localized("main.commandPalette.checkForUpdatesSubtitle"),
                group: .releases,
                keywords: ["release", "update", "version", "sparkle"],
                isGlobal: true,
                kind: .command(.checkForUpdates)
            ),
            CommandPaletteItem(
                id: "open-latest-release",
                title: localized("main.commandPalette.openLatestRelease"),
                subtitle: localized("main.commandPalette.openLatestReleaseSubtitle"),
                group: .releases,
                keywords: ["release", "notes", "download"],
                isGlobal: true,
                kind: .command(.openLatestRelease)
            ),
        ]

        items.append(
            contentsOf: LineyFeatureRegistry.shared.commandPaletteItems(
                context: LineyExtensionContext(
                    selectedWorkspace: selectedWorkspace,
                    workspaces: workspaces
                )
            )
        )

        if let selectedWorkspace {
            items.append(
                CommandPaletteItem(
                    id: "workspace-selected-session:\(selectedWorkspace.id.uuidString)",
                    title: localizedFormat("main.commandPalette.newSessionInFormat", selectedWorkspace.name),
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
                    title: localizedFormat("main.commandPalette.splitRightInFormat", selectedWorkspace.name),
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
                    title: localizedFormat("main.commandPalette.splitDownInFormat", selectedWorkspace.name),
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
                        title: localizedFormat("main.commandPalette.runSetupScriptInFormat", selectedWorkspace.name),
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
                        title: localizedFormat("main.commandPalette.runPreferredWorkflowInFormat", selectedWorkspace.name),
                        subtitle: workflow.name,
                        group: .workflows,
                        keywords: ["playbook", "workflow", "automation"],
                        isGlobal: false,
                        kind: .command(.runWorkflow(selectedWorkspace.id, workflow.id))
                    )
                )
            }
            if availableHAPIInstallation != nil {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-selected-hapi:\(selectedWorkspace.id.uuidString)",
                        title: localizedFormat("main.hapi.commandPalette.launchInFormat", selectedWorkspace.name),
                        subtitle: selectedWorkspace.activeWorktreePath,
                        group: .sessions,
                        keywords: ["hapi", "remote", "quick start", "phone", "claude"],
                        isGlobal: false,
                        kind: .command(.launchHAPISession(selectedWorkspace.id))
                    )
                )
                items.append(
                    CommandPaletteItem(
                        id: "workspace-selected-hapi-hub:\(selectedWorkspace.id.uuidString)",
                        title: localizedFormat("main.hapi.commandPalette.startHubInFormat", selectedWorkspace.name),
                        subtitle: "hapi hub --relay",
                        group: .automation,
                        keywords: ["hapi", "hub", "relay", "remote", "quick start"],
                        isGlobal: false,
                        kind: .command(.startHAPIHub(selectedWorkspace.id))
                    )
                )
            }
        }

        for workspace in workspaces {
            items.append(
                CommandPaletteItem(
                    id: "workspace:\(workspace.id.uuidString)",
                    title: localizedFormat("main.commandPalette.openWorkspaceFormat", workspace.name),
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
                    title: localizedFormat("main.commandPalette.refreshWorkspaceFormat", workspace.name),
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
                    title: localizedFormat("main.commandPalette.newSessionInFormat", workspace.name),
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
                        title: localizedFormat("main.commandPalette.openRemoteShellFormat", remoteTarget.name),
                        subtitle: remoteTarget.ssh.destination,
                        group: .sessions,
                        keywords: ["ssh", "remote", "shell", workspace.name],
                        isGlobal: false,
                        kind: .command(.openRemoteTargetShell(workspace.id, remoteTarget.id))
                    )
                )
                items.append(
                    CommandPaletteItem(
                        id: "remote-browse:\(workspace.id.uuidString):\(remoteTarget.id.uuidString)",
                        title: localizedFormat("main.commandPalette.browseRemoteRepositoryFormat", remoteTarget.name),
                        subtitle: remoteTarget.ssh.remoteWorkingDirectory ?? remoteTarget.ssh.destination,
                        group: .sessions,
                        keywords: ["ssh", "remote", "repo", "browse", "git", workspace.name],
                        isGlobal: false,
                        kind: .command(.browseRemoteTargetRepository(workspace.id, remoteTarget.id))
                    )
                )
                items.append(
                    CommandPaletteItem(
                        id: "remote-copy-destination:\(workspace.id.uuidString):\(remoteTarget.id.uuidString)",
                        title: localizedFormat("main.commandPalette.copyRemoteDestinationFormat", remoteTarget.name),
                        subtitle: remoteTarget.ssh.destination,
                        group: .navigation,
                        keywords: ["ssh", "remote", "copy", "host", workspace.name],
                        isGlobal: false,
                        kind: .command(.copyRemoteTargetDestination(workspace.id, remoteTarget.id))
                    )
                )
                if remoteTarget.ssh.remoteWorkingDirectory?.isEmpty == false {
                    items.append(
                        CommandPaletteItem(
                            id: "remote-copy-path:\(workspace.id.uuidString):\(remoteTarget.id.uuidString)",
                            title: localizedFormat("main.commandPalette.copyRemotePathFormat", remoteTarget.name),
                            subtitle: remoteTarget.ssh.remoteWorkingDirectory,
                            group: .navigation,
                            keywords: ["ssh", "remote", "copy", "path", "workspace", workspace.name],
                            isGlobal: false,
                            kind: .command(.copyRemoteTargetWorkingDirectory(workspace.id, remoteTarget.id))
                        )
                    )
                }
                if let presetID = remoteTarget.agentPresetID,
                   let preset = appSettings.agentPresets.first(where: { $0.id == presetID }) {
                    items.append(
                        CommandPaletteItem(
                            id: "remote-agent:\(workspace.id.uuidString):\(remoteTarget.id.uuidString)",
                            title: localizedFormat("main.commandPalette.launchRemoteAgentFormat", remoteTarget.name),
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
                    title: workspace.isPinned ? localizedFormat("main.commandPalette.unpinWorkspaceFormat", workspace.name) : localizedFormat("main.commandPalette.pinWorkspaceFormat", workspace.name),
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
                    title: workspace.isArchived ? localizedFormat("main.commandPalette.unarchiveWorkspaceFormat", workspace.name) : localizedFormat("main.commandPalette.archiveWorkspaceFormat", workspace.name),
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
                        title: localizedFormat("main.commandPalette.createWorktreeInFormat", workspace.name),
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
                        title: localizedFormat("main.commandPalette.newSSHSessionInFormat", workspace.name),
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
                        title: localizedFormat("main.commandPalette.newAgentSessionInFormat", workspace.name),
                        subtitle: preferredAgentPreset?.name,
                        group: .sessions,
                        keywords: ["ai", "agent", "codex"],
                        isGlobal: false,
                        kind: .command(.createAgentSession(workspace.id, preferredAgentPreset))
                    )
                )
            }
            if availableHAPIInstallation != nil {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-hapi:\(workspace.id.uuidString)",
                        title: localizedFormat("main.hapi.commandPalette.launchInFormat", workspace.name),
                        subtitle: workspace.activeWorktreePath,
                        group: .sessions,
                        keywords: ["hapi", "remote", "quick start", "phone", workspace.name],
                        isGlobal: false,
                        kind: .command(.launchHAPISession(workspace.id))
                    )
                )
                items.append(
                    CommandPaletteItem(
                        id: "workspace-hapi-hub:\(workspace.id.uuidString)",
                        title: localizedFormat("main.hapi.commandPalette.startHubInFormat", workspace.name),
                        subtitle: "hapi hub --relay",
                        group: .automation,
                        keywords: ["hapi", "hub", "relay", "remote", workspace.name],
                        isGlobal: false,
                        kind: .command(.startHAPIHub(workspace.id))
                    )
                )
            }
            if !workspace.setupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(
                    CommandPaletteItem(
                        id: "workspace-setup:\(workspace.id.uuidString)",
                        title: localizedFormat("main.commandPalette.runSetupScriptInFormat", workspace.name),
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
                        title: localizedFormat("main.commandPalette.runScriptInFormat", workspace.name),
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
                        title: localizedFormat("main.commandPalette.runWorkflowFormat", workflow.name),
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
        LocalizationManager.shared.updateSelectedLanguage(appSettings.appLanguage)
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
        panel.prompt = localized("main.openPanel.prompt")
        panel.message = localized("main.openPanel.message")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await addWorkspace(at: url)
        }
    }

    func addWorkspace(at url: URL) async {
        let normalizedPath = url.standardizedFileURL.path
        do {
            try await openRepositoryWorkspace(at: normalizedPath, persistAfterChange: false)
            persist()
        } catch GitServiceError.notAGitRepository {
            addLocalWorkspace(atPath: normalizedPath)
        } catch {
            presentError(title: localized("main.error.openRepository.title"), message: error.localizedDescription)
        }
    }

    func openWorkspaceAsRepository(_ workspace: WorkspaceModel) {
        guard !workspace.supportsRepositoryFeatures else { return }
        Task { @MainActor in
            do {
                try await openWorkspaceAsRepository(workspace, persistAfterChange: true)
            } catch {
                presentError(title: localized("main.error.openRepository.title"), message: error.localizedDescription)
            }
        }
    }

    func openWorkspaceAsRepository(
        _ workspace: WorkspaceModel,
        persistAfterChange: Bool
    ) async throws {
        guard !workspace.supportsRepositoryFeatures else { return }
        try await openRepositoryWorkspace(
            at: workspace.activeWorktreePath,
            persistAfterChange: persistAfterChange
        )
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
            appLanguage: settings.appLanguage,
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
            uiScale: settings.uiScale,
            terminalFontFamily: settings.terminalFontFamily,
            terminalFontSize: settings.terminalFontSize,
            sidebarShowsSecondaryLabels: settings.sidebarShowsSecondaryLabels,
            sidebarShowsWorkspaceBadges: settings.sidebarShowsWorkspaceBadges,
            sidebarShowsWorktreeBadges: settings.sidebarShowsWorktreeBadges,
            defaultRepositoryIcon: settings.defaultRepositoryIcon,
            defaultLocalTerminalIcon: settings.defaultLocalTerminalIcon,
            defaultWorktreeIcon: settings.defaultWorktreeIcon,
            preferredExternalEditor: settings.preferredExternalEditor,
            quickCommandCategories: settings.quickCommandCategories,
            quickCommandPresets: settings.quickCommandPresets,
            quickCommandRecentIDs: settings.quickCommandRecentIDs,
            releaseChannel: settings.releaseChannel,
            commandPaletteRecents: settings.commandPaletteRecents,
            agentPresets: settings.agentPresets,
            preferredAgentPresetID: settings.preferredAgentPresetID,
            sshPresets: settings.sshPresets,
            preferredSSHPresetID: settings.preferredSSHPresetID,
            keyboardShortcutOverrides: settings.keyboardShortcutOverrides
        )
        LocalizationManager.shared.updateSelectedLanguage(appSettings.appLanguage)
        let validAgentPresetIDs = Set(appSettings.agentPresets.map(\.id))
        for workspace in workspaces {
            workspace.settings = normalizedWorkspaceSettings(
                workspace.settings,
                for: workspace,
                validAgentPresetIDs: validAgentPresetIDs
            )
        }
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
        if let override = workspace.iconOverride(for: worktree.path) {
            return override
        }

        if appSettings.defaultWorktreeIcon != .worktreeDefault {
            return appSettings.defaultWorktreeIcon
        }

        let generatedIcons = SidebarItemIcon.generatedWorktreeIcons(
            seedSourcesByID: Dictionary(
                uniqueKeysWithValues: workspace.worktrees.map { candidate in
                    (candidate.path, worktreeIconSeed(for: candidate, in: workspace))
                }
            ),
            overrides: workspace.settings.worktreeIconOverrides
        )

        return generatedIcons[worktree.path] ?? .randomRepository(
            preferredSeed: worktreeIconSeed(for: worktree, in: workspace),
            avoiding: []
        )
    }

    private func worktreeIconSeed(for worktree: WorktreeModel, in workspace: WorkspaceModel) -> String {
        let repositoryName = URL(fileURLWithPath: workspace.repositoryRoot).lastPathComponent
        return "\(repositoryName)|\(worktree.displayName)|\(worktree.path)"
    }

    func sidebarIconRequestTitle(_ request: SidebarIconCustomizationRequest) -> String {
        switch request.target {
        case .workspace(let workspaceID):
            return workspace(for: workspaceID)?.name ?? localized("main.sidebarIcon.workspaceFallback")
        case .worktree(let workspaceID, let worktreePath):
            guard let workspace = workspace(for: workspaceID),
                  let worktree = workspace.worktrees.first(where: { $0.path == worktreePath }) else {
                return URL(fileURLWithPath: worktreePath).lastPathComponent
            }
            return "\(workspace.name) / \(worktree.displayName)"
        case .appDefaultRepository:
            return localized("main.sidebarIcon.defaultRepository")
        case .appDefaultLocalTerminal:
            return localized("main.sidebarIcon.defaultTerminal")
        case .appDefaultWorktree:
            return localized("main.sidebarIcon.defaultWorktree")
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
                    localizedFormat("main.sleepPrevention.error.startFormat", error.localizedDescription),
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

    func updateQuickCommands(
        commands: [QuickCommandPreset],
        categories: [QuickCommandCategory]
    ) {
        var settings = appSettings
        settings.quickCommandCategories = QuickCommandCatalog.normalizedCategories(categories)
        settings.quickCommandPresets = QuickCommandCatalog.normalizedCommands(
            commands,
            categories: settings.quickCommandCategories,
            reservedShortcuts: LineyKeyboardShortcuts.effectiveShortcuts(in: settings)
        )
        settings.quickCommandRecentIDs = QuickCommandCatalog.normalizedRecentCommandIDs(
            settings.quickCommandRecentIDs,
            availableCommands: settings.quickCommandPresets
        )
        appSettings = settings
        persistAppSettings()
    }

    func updateQuickCommandPresets(_ commands: [QuickCommandPreset]) {
        updateQuickCommands(commands: commands, categories: appSettings.quickCommandCategories)
    }

    func resetQuickCommandPresetsToDefaults() {
        updateQuickCommands(
            commands: QuickCommandCatalog.defaultCommands,
            categories: QuickCommandCatalog.defaultCategories
        )
    }

    func insertQuickCommand(_ preset: QuickCommandPreset) {
        guard let workspace = selectedWorkspace else {
            receive(.statusMessage(localized("main.status.quickCommand.selectWorkspace"), .warning, deliverSystemNotification: false))
            return
        }

        let targetPaneID = workspace.sessionController.focusedPaneID ?? workspace.paneOrder.first
        guard let targetPaneID,
              let session = workspace.sessionController.session(for: targetPaneID) else {
            receive(.statusMessage(localized("main.status.quickCommand.focusPane"), .warning, deliverSystemNotification: false))
            return
        }

        workspace.sessionController.focus(targetPaneID)
        switch lineyQuickCommandDispatch(for: preset) {
        case .insert(let text):
            session.insertText(text)
            receive(
                .statusMessage(
                    localizedFormat("main.status.quickCommand.insertedFormat", preset.normalizedTitle),
                    .neutral,
                    deliverSystemNotification: false
                )
            )
        case .run(let command):
            session.sendShellCommand(command)
            receive(
                .statusMessage(
                    localizedFormat("main.status.quickCommand.ranFormat", preset.normalizedTitle),
                    .success,
                    deliverSystemNotification: false
                )
            )
        }
        recordQuickCommandUse(preset.id)
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
            presentError(title: localized("main.error.refreshRepository.title"), message: error.localizedDescription)
        }
    }

    func fetch(_ workspace: WorkspaceModel) {
        guard workspace.supportsRepositoryFeatures else { return }
        Task { @MainActor in
            do {
                try await gitRepositoryService.fetch(for: workspace.repositoryRoot)
                await refreshWorkspace(workspace)
            } catch {
                presentError(title: localized("main.error.gitFetchFailed.title"), message: error.localizedDescription)
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
        guard workspace.activeWorktreePath != worktree.path else {
            workspace.createPane(splitAxis: axis)
            persist()
            return
        }

        let backendConfiguration: SessionBackendConfiguration = {
            guard let focusedPaneID = workspace.sessionController.focusedPaneID,
                  let session = workspace.sessionController.session(for: focusedPaneID),
                  session.backendConfiguration.kind == .localShell else {
                return .local()
            }
            return session.backendConfiguration
        }()

        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: worktree.path,
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: backendConfiguration
        )
        workspace.createPane(splitAxis: axis, snapshot: snapshot)
        selectWorkspace(workspace)
        persist()
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
            defaultWorkingDirectory: workspace.activeWorktreePath,
            remoteTargets: workspace.remoteTargets.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            },
            presets: appSettings.sshPresets,
            preferredPresetID: nil
        )
    }

    func presentCreateAgentSession(for workspace: WorkspaceModel) {
        createAgentSessionRequest = CreateAgentSessionRequest(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            defaultWorkingDirectory: workspace.activeWorktreePath,
            presets: appSettings.agentPresets,
            preferredPresetID: appSettings.preferredAgentPresetID ?? appSettings.agentPresets.first?.id ?? AgentPreset.claudeCode.id
        )
    }

    func createSSHSession(workspaceID: UUID, draft: CreateSSHSessionDraft) {
        guard let configuration = draft.configuration,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let workspace = workspaces[workspaceIndex]
        rememberSSHPresetSelection(selectedPresetID: draft.selectedPresetID)

        if let target = draft.targetToSave {
            if let existingIndex = workspace.remoteTargets.firstIndex(where: { $0.id == target.id }) {
                workspaces[workspaceIndex].remoteTargets[existingIndex] = target
            } else if let matchingIndex = workspace.remoteTargets.firstIndex(where: {
                $0.name.caseInsensitiveCompare(target.name) == .orderedSame
            }) {
                workspaces[workspaceIndex].remoteTargets[matchingIndex] = target
            } else {
                workspaces[workspaceIndex].remoteTargets.append(target)
            }
        }

        createSession(
            in: workspaces[workspaceIndex],
            backendConfiguration: .ssh(configuration),
            workingDirectory: workspaces[workspaceIndex].activeWorktreePath
        )
        recordActivity(
            in: workspaces[workspaceIndex],
            kind: .remote,
            title: "Opened SSH session",
            detail: configuration.destination,
            worktreePath: workspaces[workspaceIndex].activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .ssh(configuration),
                workingDirectory: workspaces[workspaceIndex].activeWorktreePath
            )
        )
        persist()
    }

    func rememberSSHPresetSelection(selectedPresetID: UUID?) {
        let updatedSelection = lineyRememberedSSHPresetSelection(
            currentPresets: appSettings.sshPresets,
            selectedPresetID: selectedPresetID
        )
        appSettings.sshPresets = updatedSelection.presets
        appSettings.preferredSSHPresetID = updatedSelection.preferredPresetID
        persistAppSettings()
    }

    func createAgentSession(workspaceID: UUID, draft: CreateAgentSessionDraft) {
        guard let configuration = draft.configuration,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        rememberAgentPresetSelection(selectedPresetID: draft.selectedPresetID)

        createSession(
            in: workspaces[workspaceIndex],
            backendConfiguration: .agent(configuration),
            workingDirectory: configuration.workingDirectory ?? workspaces[workspaceIndex].activeWorktreePath
        )
        recordActivity(
            in: workspaces[workspaceIndex],
            kind: .agent,
            title: "Opened agent session",
            detail: configuration.name,
            worktreePath: workspaces[workspaceIndex].activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(configuration),
                workingDirectory: configuration.workingDirectory ?? workspaces[workspaceIndex].activeWorktreePath
            )
        )
    }

    func rememberAgentPresetSelection(selectedPresetID: UUID?) {
        let updatedSelection = lineyRememberedAgentPresetSelection(
            currentPresets: appSettings.agentPresets,
            selectedPresetID: selectedPresetID
        )
        appSettings.agentPresets = updatedSelection.presets
        appSettings.preferredAgentPresetID = updatedSelection.preferredPresetID
        persistAppSettings()
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

    func refreshHAPIIntegrationStatus() async {
        hapiIntegrationState = await HAPIIntegrationCatalog.detect()
    }

    func performPrimaryHAPIAction() {
        guard availableHAPIInstallation != nil else {
            receive(.statusMessage(localized("status.hapi.installToEnable"), .warning, deliverSystemNotification: false))
            return
        }
        guard let workspace = selectedWorkspace else {
            receive(.statusMessage(localized("status.hapi.selectWorkspace"), .warning, deliverSystemNotification: false))
            return
        }
        startHAPIHub(in: workspace, relay: false)
    }

    func launchHAPISession(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchHAPISession(in: workspace)
    }

    func startHAPIHub(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        startHAPIHub(in: workspace, relay: false)
    }

    func startHAPIHubRelay(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        startHAPIHub(in: workspace, relay: true)
    }

    func launchHAPICodex(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchHAPISubcommand(in: workspace, name: "HAPI Codex", arguments: ["codex"])
    }

    func launchHAPICursor(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchHAPISubcommand(in: workspace, name: "HAPI Cursor", arguments: ["cursor"])
    }

    func launchHAPIGemini(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchHAPISubcommand(in: workspace, name: "HAPI Gemini", arguments: ["gemini"])
    }

    func launchHAPIOpenCode(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchHAPISubcommand(in: workspace, name: "HAPI OpenCode", arguments: ["opencode"])
    }

    func showHAPIAuthStatus(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "HAPI Auth Status",
            executablePath: availableHAPIInstallation?.executablePath,
            arguments: ["auth", "status"],
            activityTitle: localized("activity.hapi.showedAuthStatus")
        )
    }

    func loginToHAPI(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "HAPI Auth Login",
            executablePath: availableHAPIInstallation?.executablePath,
            arguments: ["auth", "login"],
            activityTitle: localized("activity.hapi.startedLogin")
        )
    }

    func logoutFromHAPI(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "HAPI Auth Logout",
            executablePath: availableHAPIInstallation?.executablePath,
            arguments: ["auth", "logout"],
            activityTitle: localized("activity.hapi.startedLogout")
        )
    }

    func showHAPISettings(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "HAPI Show Settings",
            executablePath: "/bin/cat",
            arguments: [NSHomeDirectory() + "/.hapi/settings.json"],
            activityTitle: localized("activity.hapi.showedSettings")
        )
    }

    func launchCloudflaredTunnel(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "Cloudflared Tunnel",
            executablePath: availableHAPIInstallation?.cloudflaredExecutablePath,
            arguments: ["tunnel", "--url", "http://localhost:3006"],
            activityTitle: localized("activity.cloudflared.startedTunnelProxy"),
            missingExecutableMessage: localized("status.hapi.installCloudflaredToLaunch")
        )
    }

    func loginToCloudflaredTunnel(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "Cloudflared Tunnel Login",
            executablePath: availableHAPIInstallation?.cloudflaredExecutablePath,
            arguments: ["tunnel", "login"],
            activityTitle: localized("activity.cloudflared.startedTunnelLogin"),
            missingExecutableMessage: localized("status.hapi.installCloudflaredToLaunch")
        )
    }

    func runCloudflaredTunnel(workspaceID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        launchWrappedHomeCommand(
            in: workspace,
            name: "Cloudflared Tunnel Run",
            executablePath: availableHAPIInstallation?.cloudflaredExecutablePath,
            arguments: ["tunnel", "run"],
            activityTitle: localized("activity.cloudflared.startedTunnelRun"),
            missingExecutableMessage: localized("status.hapi.installCloudflaredToLaunch")
        )
    }

    private func launchHAPISession(in workspace: WorkspaceModel) {
        guard let installation = availableHAPIInstallation else {
            receive(.statusMessage(localized("status.hapi.installToLaunch"), .warning, deliverSystemNotification: false))
            return
        }

        let configuration = AgentSessionConfiguration(
            name: "HAPI",
            launchPath: installation.executablePath,
            arguments: [],
            environment: [:],
            workingDirectory: workspace.activeWorktreePath
        )

        createSession(
            in: workspace,
            backendConfiguration: .agent(configuration),
            workingDirectory: workspace.activeWorktreePath
        )
        recordActivity(
            in: workspace,
            kind: .agent,
            title: localized("activity.hapi.launched"),
            detail: workspace.activeWorktreePath,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(configuration),
                workingDirectory: workspace.activeWorktreePath
            )
        )
    }

    private func launchHAPISubcommand(
        in workspace: WorkspaceModel,
        name: String,
        arguments: [String]
    ) {
        guard let installation = availableHAPIInstallation else {
            receive(.statusMessage(localized("status.hapi.installToLaunch"), .warning, deliverSystemNotification: false))
            return
        }

        let configuration = AgentSessionConfiguration(
            name: name,
            launchPath: installation.executablePath,
            arguments: arguments,
            environment: [:],
            workingDirectory: workspace.activeWorktreePath
        )

        createSession(
            in: workspace,
            backendConfiguration: .agent(configuration),
            workingDirectory: workspace.activeWorktreePath
        )
        recordActivity(
            in: workspace,
            kind: .agent,
            title: name,
            detail: ([installation.executablePath] + arguments).joined(separator: " "),
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(configuration),
                workingDirectory: workspace.activeWorktreePath
            )
        )
    }

    private func launchWrappedHomeCommand(
        in workspace: WorkspaceModel,
        name: String,
        executablePath: String?,
        arguments: [String],
        activityTitle: String,
        missingExecutableMessage: String? = nil
    ) {
        guard let executablePath else {
            receive(.statusMessage(missingExecutableMessage ?? localized("status.hapi.installToLaunch"), .warning, deliverSystemNotification: false))
            return
        }

        let workingDirectory = NSHomeDirectory()
        let loginShellPath = CurrentUserLoginShell.path()?.nilIfEmpty ?? "/bin/zsh"
        let invocation = ([executablePath] + arguments)
            .map(\.shellQuoted)
            .joined(separator: " ")
        let shellScript = """
        \(invocation)
        status=$?
        if [ "$status" -ne 0 ]; then
          printf '\\nCommand exited with status %d.\\n' "$status"
        fi
        printf '\\n'
        exec \(loginShellPath.shellQuoted) -l
        """
        let configuration = AgentSessionConfiguration(
            name: name,
            launchPath: "/bin/zsh",
            arguments: ["-lc", shellScript],
            environment: ["SHELL": loginShellPath],
            workingDirectory: workingDirectory
        )

        createSession(
            in: workspace,
            backendConfiguration: .agent(configuration),
            workingDirectory: workingDirectory
        )
        recordActivity(
            in: workspace,
            kind: .command,
            title: activityTitle,
            detail: ([executablePath] + arguments).joined(separator: " "),
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(configuration),
                workingDirectory: workingDirectory
            )
        )
    }

    private func startHAPIHub(in workspace: WorkspaceModel, relay: Bool) {
        guard let installation = availableHAPIInstallation else {
            receive(.statusMessage(localized("status.hapi.installToStartHub"), .warning, deliverSystemNotification: false))
            return
        }

        let workingDirectory = NSHomeDirectory()
        let arguments = relay ? ["hub", "--relay"] : ["hub"]
        let configuration = AgentSessionConfiguration(
            name: "HAPI Hub",
            launchPath: installation.executablePath,
            arguments: arguments,
            environment: [:],
            workingDirectory: workingDirectory
        )

        createSession(
            in: workspace,
            backendConfiguration: .agent(configuration),
            workingDirectory: workingDirectory
        )
        recordActivity(
            in: workspace,
            kind: .command,
            title: localized("activity.hapi.startedHub"),
            detail: ([installation.executablePath] + arguments).joined(separator: " "),
            worktreePath: workspace.activeWorktreePath,
            replayAction: .createSession(
                backendConfiguration: .agent(configuration),
                workingDirectory: workingDirectory
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
            presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.directoryRequired"))
            return false
        }
        guard !normalizedBranchName.isEmpty else {
            presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.branchRequired"))
            return false
        }
        guard !normalizedBranchName.contains(" ") else {
            presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.branchNoSpaces"))
            return false
        }
        guard !FileManager.default.fileExists(atPath: normalizedDirectoryPath) else {
            presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.pathExists"))
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
                presentError(title: localized("main.error.createWorktree.title"), message: error.localizedDescription)
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
            presentError(title: localized("main.error.removeMainWorktree.title"), message: localized("main.error.removeMainWorktree.message"))
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
                presentError(title: localized("main.error.removeWorktree.title"), message: error.localizedDescription)
            }
        }
    }

    func dispatch(_ command: WorkspaceCommand) {
        switch command {
        case .openLineyWebsite:
            dismissCommandPalette()
            openLineyWebsite()

        case .submitLineyFeedback:
            dismissCommandPalette()
            submitLineyFeedback()

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

        case .launchHAPISession(let id):
            dismissCommandPalette()
            launchHAPISession(workspaceID: id)

        case .startHAPIHub(let id):
            dismissCommandPalette()
            startHAPIHub(workspaceID: id)

        case .openRemoteTargetShell(let workspaceID, let targetID):
            dismissCommandPalette()
            openRemoteTargetShell(workspaceID: workspaceID, targetID: targetID)

        case .openRemoteTargetAgent(let workspaceID, let targetID):
            dismissCommandPalette()
            openRemoteTargetAgent(workspaceID: workspaceID, targetID: targetID)

        case .browseRemoteTargetRepository(let workspaceID, let targetID):
            dismissCommandPalette()
            browseRemoteTargetRepository(workspaceID: workspaceID, targetID: targetID)

        case .copyRemoteTargetDestination(let workspaceID, let targetID):
            dismissCommandPalette()
            copyRemoteTargetDestination(workspaceID: workspaceID, targetID: targetID)

        case .copyRemoteTargetWorkingDirectory(let workspaceID, let targetID):
            dismissCommandPalette()
            copyRemoteTargetWorkingDirectory(workspaceID: workspaceID, targetID: targetID)

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
            presentedError = PresentedError(title: localized("main.error.saveState.title"), message: error.localizedDescription)
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
        receive(.statusMessage(localized("main.status.timelineCleared"), .neutral, deliverSystemNotification: false))
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
                        ? localized("main.sleepPrevention.started.forever")
                        : localizedFormat("main.sleepPrevention.started.timedFormat", session.option.title.lowercased()),
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
                receive(.statusMessage(localized("main.sleepPrevention.stopped"), .neutral, deliverSystemNotification: false))
            case .completed:
                guard previousSession != nil else { return }
                receive(.statusMessage(localized("main.sleepPrevention.finished"), .neutral, deliverSystemNotification: false))
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
                    localized("main.status.externalEditor.installHint"),
                    .warning,
                    deliverSystemNotification: false
                )
            )
            return
        }

        if editor.editor != preferredEditor {
            receive(
                .statusMessage(
                    localizedFormat("main.status.externalEditor.fallbackFormat", preferredEditor.displayName, editor.editor.displayName),
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
                    self.localizedFormat("main.status.externalEditor.openFailedFormat", workspaceName, editor.editor.displayName, error.localizedDescription),
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
            presentedError = PresentedError(title: localized("main.error.saveSettings.title"), message: error.localizedDescription)
        }
    }

    private func workspace(for id: UUID) -> WorkspaceModel? {
        workspaces.first(where: { $0.id == id })
    }

    func openRepositoryWorkspace(
        at path: String,
        persistAfterChange: Bool
    ) async throws {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let snapshot = try await gitRepositoryService.inspectRepository(at: normalizedPath)

        if let existing = workspaces.first(where: {
            $0.supportsRepositoryFeatures && $0.repositoryRoot == snapshot.rootPath
        }) {
            selectedWorkspaceID = existing.id
            await refreshWorkspace(existing, persistAfterRefresh: persistAfterChange)
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
        if persistAfterChange {
            persist()
        }
    }

    private func normalizedWorkspaceSettings(
        _ settings: WorkspaceSettings,
        for workspace: WorkspaceModel,
        validAgentPresetIDs: Set<UUID>? = nil
    ) -> WorkspaceSettings {
        var normalized = settings
        let validSSHPresetIDs = Set(appSettings.sshPresets.map(\.id))

        if normalized.agentPresets.isEmpty {
            normalized.agentPresets = AgentPreset.builtInPresets
        }

        normalized.agentPresets.removeAll { $0.id == AgentPreset.deprecatedAiderPresetID }
        if normalized.agentPresets.isEmpty {
            normalized.agentPresets = AgentPreset.builtInPresets
        }

        let validPresetIDs = validAgentPresetIDs ?? Set(normalized.agentPresets.map(\.id))
        if let preferredAgentPresetID = normalized.preferredAgentPresetID,
           !validPresetIDs.contains(preferredAgentPresetID) {
            normalized.preferredAgentPresetID = nil
        } else if normalized.preferredAgentPresetID == nil {
            normalized.preferredAgentPresetID = nil
        }

        normalized.remoteTargets = normalized.remoteTargets.map { target in
            var updated = target
            if let sshPresetID = target.sshPresetID, !validSSHPresetIDs.contains(sshPresetID) {
                updated.sshPresetID = nil
            }
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
        notifyGitHubFeatureRemoval(localized("main.github.removed.openPullRequests"))
    }

    private func markPullRequestReady(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.markPullRequestsReady"))
    }

    private func updatePullRequestBranch(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.updatePullRequestBranches"))
    }

    private func queuePullRequest(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.queuePullRequests"))
    }

    private func updatePullRequestBranches(_ targets: [WorkspaceGitHubTarget]) async {
        _ = targets
        notifyGitHubFeatureRemoval(localized("main.github.removed.batchUpdatePullRequests"))
    }

    private func queuePullRequests(_ targets: [WorkspaceGitHubTarget]) async {
        _ = targets
        notifyGitHubFeatureRemoval(localized("main.github.removed.batchQueuePullRequests"))
    }

    private func copyPullRequestReleaseNotes(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.releaseNoteDrafting"))
    }

    private func copyPullRequestReleaseNotesBatch(_ targets: [WorkspaceGitHubTarget]) async {
        _ = targets
        notifyGitHubFeatureRemoval(localized("main.github.removed.batchReleaseNoteDrafting"))
    }

    private func openLatestRun(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.openCIRuns"))
    }

    private func openFailingCheckDetails(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.openFailingChecks"))
    }

    private func copyFailingCheckURL(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.copyFailingCheckURLs"))
    }

    private func rerunLatestFailedJobs(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.rerunCIJobs"))
    }

    private func copyLatestRunLogs(workspaceID: UUID, worktreePath: String) async {
        _ = workspaceID
        _ = worktreePath
        notifyGitHubFeatureRemoval(localized("main.github.removed.copyCILogs"))
    }

    private func openLatestRelease() {
        NSWorkspace.shared.open(AppUpdaterController.releasesURL)
        receive(.statusMessage(localized("main.status.releaseNotesOpened"), .neutral, deliverSystemNotification: false))
    }

    private func openLineyWebsite() {
        guard let url = URL(string: "https://liney.dev") else { return }
        NSWorkspace.shared.open(url)
        receive(.statusMessage(localized("extension.support.websiteOpened"), .neutral, deliverSystemNotification: false))
    }

    private func submitLineyFeedback() {
        guard let url = URL(string: "https://github.com/everettjf/liney/issues/new") else { return }
        NSWorkspace.shared.open(url)
        receive(.statusMessage(localized("extension.support.feedbackOpened"), .neutral, deliverSystemNotification: false))
    }

    private func checkForUpdates() {
        configureUpdater(checkInBackground: false)
        updaterController.checkForUpdates()
        receive(.statusMessage(localized("main.status.checkingForUpdates"), .neutral, deliverSystemNotification: false))
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
            let plan = try remoteSessionCoordinator.agentPlan(
                workspace: workspace,
                targetID: targetID,
                agentPresets: appSettings.agentPresets
            )
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

    private func browseRemoteTargetRepository(workspaceID: UUID, targetID: UUID) {
        guard let workspace = workspace(for: workspaceID) else { return }
        do {
            let plan = try remoteSessionCoordinator.repositoryBrowserPlan(workspace: workspace, targetID: targetID)
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

    private func copyRemoteTargetDestination(workspaceID: UUID, targetID: UUID) {
        guard let target = workspace(for: workspaceID)?.remoteTargets.first(where: { $0.id == targetID }) else { return }
        copyPath(target.ssh.destination)
        receive(.statusMessage(localizedFormat("remote.status.copiedDestinationFormat", target.name), .success, deliverSystemNotification: false))
    }

    private func copyRemoteTargetWorkingDirectory(workspaceID: UUID, targetID: UUID) {
        guard let target = workspace(for: workspaceID)?.remoteTargets.first(where: { $0.id == targetID }),
              let path = target.ssh.remoteWorkingDirectory,
              !path.isEmpty else { return }
        copyPath(path)
        receive(.statusMessage(localizedFormat("remote.status.copiedPathFormat", target.name), .success, deliverSystemNotification: false))
    }

    private func runWorkspaceScript(in workspace: WorkspaceModel) {
        let script = workspace.runScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            receive(.statusMessage(localized("main.status.workspace.runScriptMissing"), .warning, deliverSystemNotification: false))
            return
        }
        selectWorkspace(workspace)
        if let session = localShellSession(in: workspace, mode: .reuseFocused) {
            session.sendShellCommand(script)
            recordActivity(
                in: workspace,
                kind: .command,
                title: localized("main.activity.workspaceScriptRan"),
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
            receive(.statusMessage(localized("main.status.workspace.runScriptSent"), .success, deliverSystemNotification: false))
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
                title: localized("main.activity.setupScriptRan"),
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
            receive(.statusMessage(localized("main.status.workspace.setupScriptRan"), .success, deliverSystemNotification: false))
        }
    }

    private func runWorkflow(_ workflow: WorkspaceWorkflow, in workspace: WorkspaceModel) {
        selectWorkspace(workspace)

        if workflow.runSetupScript || workflow.runWorkspaceScript || workflow.localSessionMode != .reuseFocused {
            guard let session = localShellSession(in: workspace, mode: workflow.localSessionMode) else {
                receive(.statusMessage(localized("main.status.workflow.localShellUnavailable"), .warning, deliverSystemNotification: false))
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
           let preset = appSettings.agentPresets.first(where: { $0.id == presetID }),
           workflow.agentMode != .none {
            launchWorkflowAgent(using: preset, mode: workflow.agentMode, in: workspace)
        }

        recordActivity(
            in: workspace,
            kind: .workflow,
            title: localized("main.activity.workflowRan"),
            detail: workflow.name,
            worktreePath: workspace.activeWorktreePath,
            replayAction: .runWorkflow(workflow.id)
        )
        receive(.statusMessage(localizedFormat("main.status.workflow.ranFormat", workflow.name), .success, deliverSystemNotification: false))
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
            title: localized("main.activity.workflowAgentLaunched"),
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
            receive(.statusMessage(localized("main.status.activity.replayUnavailable"), .neutral, deliverSystemNotification: false))
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
                receive(.statusMessage(localized("main.status.activity.savedWorkflowMissing"), .warning, deliverSystemNotification: false))
                return
            }
            runWorkflow(workflow, in: workspace)
        case .createSession:
            guard let backendConfiguration = action.backendConfiguration else {
                receive(.statusMessage(localized("main.status.activity.savedSessionIncomplete"), .warning, deliverSystemNotification: false))
                return
            }
            createSession(
                in: workspace,
                backendConfiguration: backendConfiguration,
                workingDirectory: action.workingDirectory ?? workspace.activeWorktreePath
            )
            receive(.statusMessage(localizedFormat("main.status.activity.replayedFormat", entry.title.lowercased()), .success, deliverSystemNotification: false))
        case .openPullRequest:
            notifyGitHubFeatureRemoval(localized("main.github.removed.openPullRequests"))
        case .markPullRequestReady:
            notifyGitHubFeatureRemoval(localized("main.github.removed.markPullRequestsReady"))
        case .openLatestRun:
            notifyGitHubFeatureRemoval(localized("main.github.removed.openCIRuns"))
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
                localizedFormat("main.github.removed.actionFormat", action),
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

    private func addLocalWorkspace(atPath path: String) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = workspaces.first(where: {
            !$0.supportsRepositoryFeatures && $0.activeWorktreePath == normalizedPath
        }) {
            selectedWorkspaceID = existing.id
            existing.bootstrapIfNeeded()
            persist()
            return
        }

        let workspaceName = URL(fileURLWithPath: normalizedPath).lastPathComponent.nilIfEmpty ?? normalizedPath
        let workspace = WorkspaceModel(localDirectoryPath: normalizedPath, name: workspaceName)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        removeDefaultLocalWorkspaceIfNeeded()
        persist()
    }

    private func removeDefaultLocalWorkspaceIfNeeded() {
        guard workspaces.count > 1 else { return }
        let localWorkspaces = workspaces.filter { !$0.supportsRepositoryFeatures }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard localWorkspaces.count == 1,
              let localWorkspace = localWorkspaces.first,
              localWorkspace.repositoryRoot == homePath,
              localWorkspace.name == "Terminal" else { return }
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

func lineyRememberedAgentPresetSelection(
    currentPresets: [AgentPreset],
    selectedPresetID: UUID?
) -> (presets: [AgentPreset], preferredPresetID: UUID?) {
    guard let selectedPresetID,
          currentPresets.contains(where: { $0.id == selectedPresetID }) else {
        return (currentPresets, currentPresets.first?.id)
    }
    return (currentPresets, selectedPresetID)
}

func lineyRememberedSSHPresetSelection(
    currentPresets: [SSHPreset],
    selectedPresetID: UUID?
) -> (presets: [SSHPreset], preferredPresetID: UUID?) {
    guard let selectedPresetID,
          currentPresets.contains(where: { $0.id == selectedPresetID }) else {
        return (currentPresets, nil)
    }
    return (currentPresets, selectedPresetID)
}
