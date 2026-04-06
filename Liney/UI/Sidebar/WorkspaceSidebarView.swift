//
//  WorkspaceSidebarView.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var query: String = ""

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var uiScale: CGFloat {
        CGFloat(store.appSettings.uiScale)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11 * uiScale, weight: .semibold))
                    .foregroundStyle(LineyTheme.mutedText)

                TextField(
                    text: $query,
                    prompt: Text(localized("sidebar.filterWorkspaces"))
                        .font(.system(size: 11 * uiScale, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                ) {
                    EmptyView()
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12 * uiScale, weight: .medium))
            }
            .padding(.horizontal, 12 * uiScale)
            .padding(.vertical, 8 * uiScale)
            .background(LineyTheme.sidebarSearchBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 8 * uiScale)
            .padding(.top, 12 * uiScale)
            .padding(.bottom, 10 * uiScale)
            .background(LineyTheme.sidebarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LineyTheme.border)
                    .frame(height: 1)
            }

            WorkspaceOutlineSidebar(query: query, onOpenRepository: store.addWorkspaceFromOpenPanel)
                .environmentObject(store)
        }
        .background(LineyTheme.sidebarBackground)
    }
}

private struct WorkspaceOutlineSidebar: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore

    let query: String
    let onOpenRepository: () -> Void

    func makeCoordinator() -> WorkspaceSidebarCoordinator {
        WorkspaceSidebarCoordinator(store: store)
    }

    func makeNSView(context: Context) -> SidebarOutlineContainerView {
        let container = SidebarOutlineContainerView()
        context.coordinator.attach(container)
        return container
    }

    func updateNSView(_ nsView: SidebarOutlineContainerView, context: Context) {
        context.coordinator.store = store
        nsView.setOpenRepositoryAction(onOpenRepository)
        context.coordinator.apply(
            workspaces: store.sidebarWorkspaces,
            selectedWorkspaceID: store.selectedWorkspaceID,
            query: query
        )
    }
}

private struct SidebarOpenRepositoryRow: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @EnvironmentObject private var store: WorkspaceStore
    let action: () -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var uiScale: CGFloat {
        CGFloat(store.appSettings.uiScale)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11 * uiScale, weight: .semibold))
                Text(localized("sidebar.openFolder"))
                    .font(.system(size: 11 * uiScale, weight: .semibold))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10 * uiScale)
            .frame(maxWidth: .infinity, minHeight: 30 * uiScale, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(LineyTheme.border)
        )
        .foregroundStyle(LineyTheme.secondaryText)
        .help(localized("sidebar.openFolderHelp"))
    }
}

@MainActor
private final class WorkspaceSidebarCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private static let workspaceDragType = NSPasteboard.PasteboardType("com.liney.workspace.ids")
    private static let groupDragType = NSPasteboard.PasteboardType("com.liney.group.id")

    weak var container: SidebarOutlineContainerView?
    weak var store: WorkspaceStore?

    private var rootNodes: [SidebarNodeItem] = []
    private var nodeLookup: [String: SidebarNodeItem] = [:]
    private var currentQuery: String = ""
    private var isApplyingSelection = false
    private var isRestoringExpansion = false
    private var isUserDrivenSelection = false
    private var suppressSelectionSync = false
    private var pinnedSelectionNodeID: String?
    private var lastDataFingerprint: String = ""

    init(store: WorkspaceStore) {
        self.store = store
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    func attach(_ container: SidebarOutlineContainerView) {
        self.container = container
        container.outlineView.dataSource = self
        container.outlineView.delegate = self
        container.outlineView.menuProvider = { [weak self] row in
            self?.contextMenu(forRow: row)
        }
        container.outlineView.activateSelection = { [weak self] modifiers in
            self?.activateSelection(modifierFlags: modifiers)
        }
        container.outlineView.toggleExpansionForSelection = { [weak self] in
            self?.toggleExpansionForSelection()
        }
        container.outlineView.target = self
        container.outlineView.doubleAction = #selector(handleDoubleClick(_:))
        container.outlineView.registerForDraggedTypes([Self.workspaceDragType, Self.groupDragType])
    }

    func apply(
        workspaces: [WorkspaceModel],
        selectedWorkspaceID: UUID?,
        query: String
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fingerprint = dataFingerprint(workspaces: workspaces, query: trimmedQuery)
        let dataChanged = fingerprint != lastDataFingerprint

        if dataChanged {
            lastDataFingerprint = fingerprint
            currentQuery = trimmedQuery
            rootNodes = buildNodes(from: workspaces)
            nodeLookup = Dictionary(uniqueKeysWithValues: rootNodes.flatMap { $0.flattened() }.map { ($0.id, $0) })

            isApplyingSelection = true
            container?.reloadOutlineData()
            guard let outlineView = container?.outlineView else { isApplyingSelection = false; return }
            isRestoringExpansion = true
            restoreExpansionState(on: outlineView)
            isRestoringExpansion = false
            container?.relayout()
            isApplyingSelection = false
            synchronizeSelection(on: outlineView, selectedWorkspaceID: selectedWorkspaceID)
        } else {
            guard let outlineView = container?.outlineView else { return }
            synchronizeSelection(on: outlineView, selectedWorkspaceID: selectedWorkspaceID)
        }
    }

    private func dataFingerprint(workspaces: [WorkspaceModel], query: String) -> String {
        var parts: [String] = [query]
        if let settings = store?.appSettings {
            let groupFingerprint = settings.workspaceGroups.map { g in
                "\(g.id)|\(g.name)|\(g.icon.symbolName)|\(g.icon.palette.rawValue)|\(g.isExpanded)|\(g.workspaceIDs.map(\.uuidString).joined(separator: ","))"
            }.joined(separator: ";")
            parts.append("groups:\(groupFingerprint)")
            let rootOrderFingerprint = settings.sidebarRootOrder.map { "\($0)" }.joined(separator: ",")
            parts.append("rootOrder:\(rootOrderFingerprint)")
            parts.append(
                [
                    settings.sidebarShowsSecondaryLabels.description,
                    settings.sidebarShowsWorkspaceBadges.description,
                    settings.sidebarShowsWorktreeBadges.description,
                    settings.defaultRepositoryIcon.symbolName,
                    settings.defaultRepositoryIcon.palette.rawValue,
                    settings.defaultRepositoryIcon.fillStyle.rawValue,
                    settings.defaultLocalTerminalIcon.symbolName,
                    settings.defaultLocalTerminalIcon.palette.rawValue,
                    settings.defaultLocalTerminalIcon.fillStyle.rawValue,
                    settings.defaultWorktreeIcon.symbolName,
                    settings.defaultWorktreeIcon.palette.rawValue,
                    settings.defaultWorktreeIcon.fillStyle.rawValue,
                ]
                .joined(separator: "|")
            )
        }
        for ws in workspaces {
                parts.append("\(ws.id)|\(ws.name)|\(ws.currentBranch)|\(ws.activeWorktreePath)|\(ws.hasUncommittedChanges)|\(ws.changedFileCount)|\(ws.aheadCount)|\(ws.behindCount)|\(ws.worktrees.count)|\(ws.activeSessionCount)|\(ws.isPinned)|\(ws.isArchived)|\(ws.workspaceIconOverride?.symbolName ?? "-")|\(ws.workspaceIconOverride?.palette.rawValue ?? "-")|\(ws.workspaceIconOverride?.fillStyle.rawValue ?? "-")|\(ws.runScript)|\(ws.workflows.map(\.name).joined(separator: ","))")
                for wt in ws.worktrees {
                    let icon = ws.iconOverride(for: wt.path)
                    parts.append("  \(wt.path)|\(wt.branch ?? "-")|\(wt.isLocked)|\(icon?.symbolName ?? "-")|\(icon?.palette.rawValue ?? "-")|\(icon?.fillStyle.rawValue ?? "-")")
                }
                if let status = ws.worktreeStatuses.values.first {
                    parts.append("  s:\(status.hasUncommittedChanges)|\(status.changedFileCount)")
            }
        }
        return parts.joined(separator: "\n")
    }

        private func buildNodes(from workspaces: [WorkspaceModel]) -> [SidebarNodeItem] {
            let groupsByID = Dictionary(
                uniqueKeysWithValues: (store?.appSettings.workspaceGroups ?? []).map { ($0.id, $0) }
            )
            let workspaceByID = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
            let rootOrder = store?.effectiveSidebarRootOrder() ?? []

            var result: [SidebarNodeItem] = []

            for rootItem in rootOrder {
                switch rootItem {
                case .group(let groupID):
                    guard let group = groupsByID[groupID] else { continue }
                    let groupWorkspaceNodes = group.workspaceIDs.compactMap { id -> SidebarNodeItem? in
                        guard let workspace = workspaceByID[id] else { return nil }
                        return makeWorkspaceNode(workspace)
                    }
                    let matchesQuery = currentQuery.isEmpty || group.name.lowercased().contains(currentQuery)
                    if matchesQuery || !groupWorkspaceNodes.isEmpty {
                        result.append(.group(group: group, children: groupWorkspaceNodes))
                    }
                case .workspace(let wsID):
                    guard let workspace = workspaceByID[wsID] else { continue }
                    if let node = makeWorkspaceNode(workspace) {
                        result.append(node)
                    }
                }
            }

            // Append fixed archive group at the bottom
            let archivedWorkspaces = store?.archivedWorkspaces ?? []
            if !archivedWorkspaces.isEmpty {
                let archiveChildren = archivedWorkspaces.compactMap { makeWorkspaceNode($0) }
                if !archiveChildren.isEmpty {
                    result.append(.archiveGroup(children: archiveChildren))
                }
            }

            return result
        }

        private func makeWorkspaceNode(_ workspace: WorkspaceModel) -> SidebarNodeItem? {
            let workspaceMatches = currentQuery.isEmpty || workspace.matchesSidebarQuery(currentQuery)
            let visibleWorktrees = workspace.supportsRepositoryFeatures
                ? filteredWorktrees(for: workspace, workspaceMatches: workspaceMatches)
                : []
            guard workspaceMatches || !visibleWorktrees.isEmpty else { return nil }

            let children: [SidebarNodeItem]
            if workspace.supportsRepositoryFeatures, visibleWorktrees.count > 1 {
                children = makeWorktreeNodes(for: workspace, worktrees: visibleWorktrees)
            } else {
                children = []
            }

            return .workspace(workspace: workspace, children: children)
        }

        private func filteredWorktrees(for workspace: WorkspaceModel, workspaceMatches: Bool) -> [WorktreeModel] {
            guard !currentQuery.isEmpty else { return workspace.worktrees }
            if workspaceMatches {
                return workspace.worktrees
            }
            return workspace.worktrees.filter { $0.matchesSidebarQuery(currentQuery) }
        }

        private func makeWorktreeNodes(for workspace: WorkspaceModel, worktrees: [WorktreeModel]) -> [SidebarNodeItem] {
            worktrees.sorted { lhs, rhs in
                if lhs.isMainWorktree { return true }
                if rhs.isMainWorktree { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .map { .worktree(workspace: workspace, worktree: $0) }
        }

        private func restoreExpansionState(on outlineView: NSOutlineView) {
            for node in rootNodes {
                switch node.kind {
                case .group(let group):
                    if group.isExpanded {
                        outlineView.expandItem(node)
                    } else {
                        outlineView.collapseItem(node)
                    }
                    for child in node.children {
                        if child.workspace?.isSidebarExpanded == true {
                            outlineView.expandItem(child)
                        } else {
                            outlineView.collapseItem(child)
                        }
                    }
                case .archiveGroup:
                    if store?.appSettings.showArchivedWorkspaces == true {
                        outlineView.expandItem(node)
                    } else {
                        outlineView.collapseItem(node)
                    }
                case .workspace:
                    if node.workspace?.isSidebarExpanded == true {
                        outlineView.expandItem(node)
                    } else {
                        outlineView.collapseItem(node)
                    }
                default:
                    break
                }
            }
        }

        private func synchronizeSelection(on outlineView: NSOutlineView, selectedWorkspaceID: UUID?) {
            guard !rootNodes.isEmpty else { return }
            if isUserDrivenSelection { isUserDrivenSelection = false; return }
            if suppressSelectionSync { return }

            let candidateIDs: [String] = {
                if let pinned = pinnedSelectionNodeID, nodeLookup[pinned] != nil {
                    return [pinned]
                }

                guard let selectedWorkspaceID,
                      let selectedWorkspace = store?.workspaces.first(where: { $0.id == selectedWorkspaceID }) else {
                    return rootNodes.first.map { [$0.id] } ?? []
                }

                var ids: [String] = []
                ids.append("workspace:\(selectedWorkspace.id.uuidString)")
                let worktreeID = "worktree:\(selectedWorkspace.id.uuidString):\(selectedWorkspace.activeWorktreePath)"
                if nodeLookup[worktreeID] != nil {
                    ids.append(worktreeID)
                }
                return ids
            }()

            let row = candidateIDs
                .compactMap { nodeLookup[$0] }
                .map { outlineView.row(forItem: $0) }
                .first(where: { $0 >= 0 })

            guard let row else { return }

            isApplyingSelection = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isApplyingSelection = false
        }

        private func selectedNodes(from outlineView: NSOutlineView) -> [SidebarNodeItem] {
            outlineView.selectedRowIndexes.compactMap { row in
                outlineView.item(atRow: row) as? SidebarNodeItem
            }
        }

        private func contextMenu(forRow row: Int) -> NSMenu? {
            guard let outlineView = container?.outlineView else { return nil }
            let selectedNodes = selectedNodes(from: outlineView)
            let effectiveNodes: [SidebarNodeItem]

            if row >= 0, let node = outlineView.item(atRow: row) as? SidebarNodeItem {
                if outlineView.selectedRowIndexes.contains(row) {
                    effectiveNodes = selectedNodes.isEmpty ? [node] : selectedNodes
                } else {
                    effectiveNodes = [node]
                }
            } else {
                effectiveNodes = []
            }

            guard !effectiveNodes.isEmpty else { return nil }

            if effectiveNodes.count > 1, effectiveNodes.allSatisfy(\.isWorkspaceNode) {
                return makeWorkspaceBatchMenu(nodes: effectiveNodes)
            }

            if effectiveNodes.count > 1,
               let (workspace, worktrees) = selectedWorktrees(from: effectiveNodes) {
                return makeWorktreeBatchMenu(workspace: workspace, worktrees: worktrees)
            }

            if effectiveNodes.count == 1, let node = effectiveNodes.first {
                switch node.kind {
                case .group(let group):
                    return makeGroupMenu(group: group)
                case .archiveGroup:
                    return nil
                case .workspace(let workspace):
                    return makeWorkspaceMenu(workspace: workspace)
                case .branch:
                    return nil
                case .worktree(let workspace, let worktree):
                    return makeWorktreeMenu(workspace: workspace, worktree: worktree)
                }
            }

            let menu = NSMenu()
            let paths = effectiveNodes.compactMap(\.path)
            if !paths.isEmpty {
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.copySelectedPaths"),
                    action: #selector(copySelectedPaths(_:)),
                    representedObject: paths
                )
            }
            return menu
        }

        @discardableResult
        private func addMenuItem(
            to menu: NSMenu,
            title: String,
            action: Selector?,
            representedObject: Any? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = representedObject
            menu.addItem(item)
            return item
        }

        private func makeWorkspaceBatchMenu(nodes: [SidebarNodeItem]) -> NSMenu {
            let menu = NSMenu()
            let workspaceIDs = nodes.compactMap(\.workspace?.id)
            let paths = nodes.compactMap(\.workspace?.activeWorktreePath)

            addMenuItem(to: menu, title: localized("sidebar.menu.refreshSelectedWorkspaces"), action: #selector(refreshSelectedWorkspaces(_:)), representedObject: workspaceIDs)
            addMenuItem(to: menu, title: localized("sidebar.menu.fetchSelectedWorkspaces"), action: #selector(fetchSelectedWorkspaces(_:)), representedObject: workspaceIDs)

            menu.addItem(.separator())
            addMenuItem(to: menu, title: localized("sidebar.menu.copySelectedPaths"), action: #selector(copySelectedPaths(_:)), representedObject: paths)
            addMenuItem(to: menu, title: localized("sidebar.menu.revealSelectedInFinder"), action: #selector(revealSelectedPaths(_:)), representedObject: paths)

            menu.addItem(.separator())

            let groups = store?.appSettings.workspaceGroups ?? []
            addMenuItem(to: menu, title: localized("sidebar.menu.group.createGroupFromSelected"), action: #selector(createGroupForWorkspace(_:)), representedObject: workspaceIDs)
            if !groups.isEmpty {
                let groupItem = NSMenuItem(title: localized("sidebar.menu.moveToGroup"), action: nil, keyEquivalent: "")
                let groupSubmenu = NSMenu()
                for group in groups {
                    addMenuItem(to: groupSubmenu, title: group.name, action: #selector(moveWorkspaceToGroup(_:)), representedObject: SidebarActionMoveToGroup(workspaceIDs: workspaceIDs, groupID: group.id))
                }
                menu.setSubmenu(groupSubmenu, for: groupItem)
                menu.addItem(groupItem)
            }

            menu.addItem(.separator())
            addMenuItem(to: menu, title: localized("sidebar.menu.removeSelectedWorkspaces"), action: #selector(removeSelectedWorkspaces(_:)), representedObject: workspaceIDs)
            return menu
        }

        private func makeGroupMenu(group: WorkspaceGroup) -> NSMenu {
            let menu = NSMenu()

            addMenuItem(to: menu, title: localized("sidebar.menu.group.refresh"), action: #selector(refreshGroup(_:)), representedObject: group.id)
            addMenuItem(to: menu, title: localized("sidebar.menu.group.fetch"), action: #selector(fetchGroup(_:)), representedObject: group.id)

            menu.addItem(.separator())
            addMenuItem(to: menu, title: localized("sidebar.menu.group.rename"), action: #selector(renameGroup(_:)), representedObject: group)
            addMenuItem(to: menu, title: localized("sidebar.menu.group.customizeIcon"), action: #selector(customizeGroupIcon(_:)), representedObject: group.id)

            menu.addItem(.separator())
            addMenuItem(to: menu, title: localized("sidebar.menu.group.remove"), action: #selector(removeGroup(_:)), representedObject: group.id)

            return menu
        }

        @objc private func refreshGroup(_ sender: NSMenuItem) {
            guard let groupID = sender.representedObject as? UUID else { return }
            store?.refreshWorkspacesInGroup(groupID)
        }

        @objc private func fetchGroup(_ sender: NSMenuItem) {
            guard let groupID = sender.representedObject as? UUID else { return }
            store?.fetchWorkspacesInGroup(groupID)
        }

        @objc private func renameGroup(_ sender: NSMenuItem) {
            guard let group = sender.representedObject as? WorkspaceGroup else { return }
            store?.renameWorkspaceRequest = RenameWorkspaceRequest(
                workspaceID: UUID(),
                currentName: group.name,
                isGroupRename: true,
                groupID: group.id
            )
        }

        @objc private func customizeGroupIcon(_ sender: NSMenuItem) {
            guard let groupID = sender.representedObject as? UUID else { return }
            store?.presentSidebarIconCustomization(for: .workspaceGroup(groupID))
        }

        @objc private func removeGroup(_ sender: NSMenuItem) {
            guard let groupID = sender.representedObject as? UUID else { return }
            store?.removeWorkspaceGroup(groupID)
        }

        @objc private func createGroupForWorkspace(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [UUID] else { return }
            store?.requestCreateWorkspaceGroup(for: ids)
        }

        @objc private func moveWorkspaceToGroup(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionMoveToGroup else { return }
            store?.assignWorkspaces(ids: payload.workspaceIDs, toGroup: payload.groupID)
        }

        @objc private func removeWorkspaceFromGroup(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID else { return }
            store?.removeWorkspacesFromAllGroups(ids: [workspaceID])
        }

        private func makeWorkspaceMenu(workspace: WorkspaceModel) -> NSMenu {
            let menu = NSMenu()

            // Dynamic actions at the top for quick access
            let hasRunScript = !workspace.runScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasRunScript {
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.runWorkspaceScript"),
                    action: #selector(runWorkspaceScript(_:)),
                    representedObject: workspace.id
                )
                menu.addItem(.separator())
            }

            if workspace.supportsRepositoryFeatures {
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.createWorktree"),
                    action: #selector(createWorktree(_:)),
                    representedObject: workspace.id
                )
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.fetchRemotes"),
                    action: #selector(fetchWorkspace(_:)),
                    representedObject: workspace.id
                )
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.refreshRepository"),
                    action: #selector(refreshWorkspace(_:)),
                    representedObject: workspace.id
                )
            } else {
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.openAsRepository"),
                    action: #selector(openWorkspaceAsRepository(_:)),
                    representedObject: workspace.id
                )
            }

            if LineyFeatureFlags.showsRemoteSessionCreationUI {
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.newSSHSession"),
                    action: #selector(newSSHSession(_:)),
                    representedObject: workspace.id
                )
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.newAgentSession"),
                    action: #selector(newAgentSession(_:)),
                    representedObject: workspace.id
                )

                menu.addItem(.separator())
            }

            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.revealInFinder"),
                action: #selector(revealPath(_:)),
                representedObject: workspace.activeWorktreePath
            )
            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.copyPath"),
                action: #selector(copyPath(_:)),
                representedObject: workspace.activeWorktreePath
            )

            menu.addItem(.separator())

            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.renameWorkspace"),
                action: #selector(renameWorkspace(_:)),
                representedObject: workspace.id
            )
            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.customizeIcon"),
                action: #selector(customizeWorkspaceIcon(_:)),
                representedObject: workspace.id
            )
            addMenuItem(
                to: menu,
                title: workspace.isPinned ? localized("sidebar.menu.unpinWorkspace") : localized("sidebar.menu.pinWorkspace"),
                action: #selector(togglePinnedWorkspace(_:)),
                representedObject: workspace.id
            )
            addMenuItem(
                to: menu,
                title: workspace.isArchived ? localized("sidebar.menu.unarchiveWorkspace") : localized("sidebar.menu.archiveWorkspace"),
                action: #selector(toggleArchivedWorkspace(_:)),
                representedObject: workspace.id
            )
            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.workspaceSettings"),
                action: #selector(openWorkspaceSettings(_:)),
                representedObject: workspace.id
            )

            menu.addItem(.separator())

            let groups = store?.appSettings.workspaceGroups ?? []
            let currentGroup = store?.workspaceGroupForWorkspace(workspace.id)

            if !groups.isEmpty || currentGroup != nil {
                let groupItem = NSMenuItem(title: localized("sidebar.menu.moveToGroup"), action: nil, keyEquivalent: "")
                let groupSubmenu = NSMenu()

                addMenuItem(to: groupSubmenu, title: localized("sidebar.menu.group.newGroup"), action: #selector(createGroupForWorkspace(_:)), representedObject: [workspace.id])

                if currentGroup != nil {
                    addMenuItem(to: groupSubmenu, title: localized("sidebar.menu.group.removeFromGroup"), action: #selector(removeWorkspaceFromGroup(_:)), representedObject: workspace.id)
                }

                if !groups.isEmpty {
                    groupSubmenu.addItem(.separator())
                }

                for group in groups {
                    let item = addMenuItem(to: groupSubmenu, title: group.name, action: #selector(moveWorkspaceToGroup(_:)), representedObject: SidebarActionMoveToGroup(workspaceIDs: [workspace.id], groupID: group.id))
                    if currentGroup?.id == group.id {
                        item.state = .on
                    }
                }

                menu.setSubmenu(groupSubmenu, for: groupItem)
                menu.addItem(groupItem)
            } else {
                addMenuItem(to: menu, title: localized("sidebar.menu.group.createGroup"), action: #selector(createGroupForWorkspace(_:)), representedObject: [workspace.id])
            }

            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.removeWorkspace"),
                action: #selector(removeWorkspace(_:)),
                representedObject: workspace.id
            )
            return menu
        }

        private func makeWorktreeBatchMenu(workspace: WorkspaceModel, worktrees: [WorktreeModel]) -> NSMenu {
            let menu = NSMenu()
            let paths = worktrees.map(\.path)

            if let first = worktrees.first {
                addMenuItem(to: menu, title: localized("sidebar.menu.switchToFirstSelected"), action: #selector(switchWorktree(_:)), representedObject: SidebarActionWorktree(workspaceID: workspace.id, worktreePath: first.path))

                let switchMenu = NSMenuItem(title: localized("sidebar.menu.switchToSelectedWorktree"), action: nil, keyEquivalent: "")
                let switchSubmenu = NSMenu()
                for worktree in worktrees {
                    addMenuItem(
                        to: switchSubmenu,
                        title: worktree.displayName,
                        action: #selector(switchWorktree(_:)),
                        representedObject: SidebarActionWorktree(workspaceID: workspace.id, worktreePath: worktree.path)
                    )
                }
                menu.setSubmenu(switchSubmenu, for: switchMenu)
                menu.addItem(switchMenu)

                addMenuItem(to: menu, title: localized("sidebar.menu.newSessionInFirstSelected"), action: #selector(newSessionForWorktree(_:)), representedObject: SidebarActionWorktree(workspaceID: workspace.id, worktreePath: first.path))
                addMenuItem(to: menu, title: localized("sidebar.menu.splitRightInFirstSelected"), action: #selector(splitRightForWorktree(_:)), representedObject: SidebarActionWorktree(workspaceID: workspace.id, worktreePath: first.path))
                addMenuItem(to: menu, title: localized("sidebar.menu.splitDownInFirstSelected"), action: #selector(splitDownForWorktree(_:)), representedObject: SidebarActionWorktree(workspaceID: workspace.id, worktreePath: first.path))
            }

            menu.addItem(.separator())
            addMenuItem(to: menu, title: localized("sidebar.menu.copySelectedPaths"), action: #selector(copySelectedPaths(_:)), representedObject: paths)
            addMenuItem(to: menu, title: localized("sidebar.menu.revealSelectedInFinder"), action: #selector(revealSelectedPaths(_:)), representedObject: paths)

            let removablePaths = worktrees.filter { !$0.isMainWorktree }.map(\.path)
            if !removablePaths.isEmpty {
                menu.addItem(.separator())
                addMenuItem(to: menu, title: localized("sidebar.menu.removeSelectedWorktrees"), action: #selector(removeSelectedWorktrees(_:)), representedObject: SidebarActionWorktreeBatch(workspaceID: workspace.id, worktreePaths: removablePaths))
            }

            menu.addItem(.separator())
            addMenuItem(to: menu, title: localized("sidebar.menu.refreshRepository"), action: #selector(refreshWorkspace(_:)), representedObject: workspace.id)
            return menu
        }

        private func makeWorktreeMenu(workspace: WorkspaceModel, worktree: WorktreeModel) -> NSMenu {
            let menu = NSMenu()
            let actionPayload = SidebarActionWorktree(workspaceID: workspace.id, worktreePath: worktree.path)

            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.revealPath"),
                action: #selector(revealPath(_:)),
                representedObject: worktree.path
            )
            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.copyPath"),
                action: #selector(copyPath(_:)),
                representedObject: worktree.path
            )

            menu.addItem(.separator())
            addMenuItem(
                to: menu,
                title: localized("menu.file.splitRight"),
                action: #selector(splitRightForWorktree(_:)),
                representedObject: actionPayload
            )
            addMenuItem(
                to: menu,
                title: localized("menu.file.splitDown"),
                action: #selector(splitDownForWorktree(_:)),
                representedObject: actionPayload
            )

            menu.addItem(.separator())
            addMenuItem(
                to: menu,
                title: localized("sidebar.menu.customizeIcon"),
                action: #selector(customizeWorktreeIcon(_:)),
                representedObject: actionPayload
            )

            if workspace.supportsRepositoryFeatures, !worktree.isMainWorktree {
                menu.addItem(.separator())
                addMenuItem(
                    to: menu,
                    title: localized("sidebar.menu.removeWorktree"),
                    action: #selector(removeWorktree(_:)),
                    representedObject: actionPayload
                )
            }
            return menu
        }

        @objc private func refreshSelectedWorkspaces(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [UUID] else { return }
            store?.refreshWorkspaces(ids: ids)
        }

        @objc private func fetchSelectedWorkspaces(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [UUID] else { return }
            store?.fetchWorkspaces(ids: ids)
        }

        @objc private func removeSelectedWorkspaces(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [UUID] else { return }
            store?.removeWorkspaces(ids: ids)
        }

        @objc private func copySelectedPaths(_ sender: NSMenuItem) {
            guard let paths = sender.representedObject as? [String] else { return }
            store?.copyPaths(paths)
        }

        @objc private func revealSelectedPaths(_ sender: NSMenuItem) {
            guard let paths = sender.representedObject as? [String] else { return }
            for path in paths {
                store?.openInFinder(path: path)
            }
        }

        @objc private func revealPath(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            store?.openInFinder(path: path)
        }

        @objc private func copyPath(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            store?.copyPath(path)
        }

        @objc private func newSession(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.createSession(in: workspace)
        }

        @objc private func createWorktree(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.presentCreateWorktree(for: workspace)
        }

        @objc private func newSSHSession(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.presentCreateSSHSession(for: workspace)
        }

        @objc private func newAgentSession(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.presentCreateAgentSession(for: workspace)
        }

        @objc private func fetchWorkspace(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.fetch(workspace)
        }

        @objc private func refreshWorkspace(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.refresh(workspace)
        }

        @objc private func openWorkspaceAsRepository(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.openWorkspaceAsRepository(workspace)
        }

        @objc private func equalizeSplits(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.equalizeSplits(in: workspace)
        }

        @objc private func renameWorkspace(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.requestRenameWorkspace(workspace)
        }

        @objc private func removeWorkspace(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.removeWorkspace(workspace)
        }

        @objc private func togglePinnedWorkspace(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID else { return }
            store?.dispatch(.toggleWorkspacePinned(workspaceID))
        }

        @objc private func customizeWorkspaceIcon(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.presentSidebarIconCustomization(for: workspace)
        }

        @objc private func toggleArchivedWorkspace(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID else { return }
            store?.dispatch(.toggleWorkspaceArchived(workspaceID))
        }

        @objc private func runWorkspaceScript(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID else { return }
            store?.dispatch(.runWorkspaceScript(workspaceID))
        }

        @objc private func runWorkflow(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorkflow else { return }
            store?.dispatch(.runWorkflow(payload.workspaceID, payload.workflowID))
        }

        @objc private func openWorkspaceSettings(_ sender: NSMenuItem) {
            guard let workspaceID = sender.representedObject as? UUID,
                  let workspace = store?.workspaces.first(where: { $0.id == workspaceID }) else { return }
            store?.presentSettings(for: workspace)
        }

        @objc private func switchWorktree(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            openWorktree(payload, action: .none)
        }

        @objc private func customizeWorktreeIcon(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree,
                  let workspace = store?.workspaces.first(where: { $0.id == payload.workspaceID }),
                  let worktree = workspace.worktrees.first(where: { $0.path == payload.worktreePath }) else { return }
            store?.presentSidebarIconCustomization(for: worktree, in: workspace)
        }

        @objc private func removeWorktree(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree,
                  let workspace = store?.workspaces.first(where: { $0.id == payload.workspaceID }),
                  let worktree = workspace.worktrees.first(where: { $0.path == payload.worktreePath }) else { return }
            store?.requestWorktreeRemoval(worktree, in: workspace)
        }

        @objc private func removeSelectedWorktrees(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktreeBatch,
                  let workspace = store?.workspaces.first(where: { $0.id == payload.workspaceID }) else { return }
            store?.requestWorktreeRemoval(paths: payload.worktreePaths, in: workspace)
        }

        @objc private func newSessionForWorktree(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            openWorktree(payload, action: .newSession)
        }

        @objc private func splitRightForWorktree(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            openWorktree(payload, action: .splitVertical)
        }

        @objc private func splitDownForWorktree(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            openWorktree(payload, action: .splitHorizontal)
        }

        @objc private func openPullRequest(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.openPullRequest(payload.workspaceID, payload.worktreePath))
        }

        @objc private func markPullRequestReady(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.markPullRequestReady(payload.workspaceID, payload.worktreePath))
        }

        @objc private func openLatestRun(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.openLatestRun(payload.workspaceID, payload.worktreePath))
        }

        @objc private func openFailingCheckDetails(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.openFailingCheckDetails(payload.workspaceID, payload.worktreePath))
        }

        @objc private func copyFailingCheckURL(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.copyFailingCheckURL(payload.workspaceID, payload.worktreePath))
        }

        @objc private func rerunLatestRun(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.rerunLatestFailedJobs(payload.workspaceID, payload.worktreePath))
        }

        @objc private func copyLatestRunLogs(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SidebarActionWorktree else { return }
            store?.dispatch(.copyLatestRunLogs(payload.workspaceID, payload.worktreePath))
        }

        private func openWorktree(_ payload: SidebarActionWorktree, action: PendingWorktreeAction) {
            guard let workspace = store?.workspaces.first(where: { $0.id == payload.workspaceID }),
                  let worktree = workspace.worktrees.first(where: { $0.path == payload.worktreePath }) else { return }
            switch action {
            case .none:
                store?.requestSwitchToWorktree(worktree, in: workspace)
            case .newSession:
                store?.createSession(in: workspace, for: worktree)
            case .splitVertical:
                store?.split(in: workspace, for: worktree, axis: .vertical)
            case .splitHorizontal:
                store?.split(in: workspace, for: worktree, axis: .horizontal)
            }
        }

        @objc private func handleDoubleClick(_ sender: Any?) {
            guard let outlineView = container?.outlineView else { return }
            let clickedRow = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
            guard clickedRow >= 0,
                  let node = outlineView.item(atRow: clickedRow) as? SidebarNodeItem else { return }
            performDefaultAction(for: node, modifierFlags: NSApp.currentEvent?.modifierFlags ?? [])
        }

        private func activateSelection(modifierFlags: NSEvent.ModifierFlags) {
            guard let outlineView = container?.outlineView else { return }
            let nodes = selectedNodes(from: outlineView)
            guard nodes.count == 1, let node = nodes.first else { return }
            performDefaultAction(for: node, modifierFlags: modifierFlags)
        }

        private func toggleExpansionForSelection() {
            guard let outlineView = container?.outlineView else { return }
            let nodes = selectedNodes(from: outlineView)
            guard nodes.count == 1, let node = nodes.first, node.isExpandable else { return }
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        }

        private func performDefaultAction(for node: SidebarNodeItem, modifierFlags: NSEvent.ModifierFlags) {
            switch node.kind {
            case .group, .archiveGroup:
                guard let outlineView = container?.outlineView else { return }
                if outlineView.isItemExpanded(node) {
                    outlineView.collapseItem(node)
                } else {
                    outlineView.expandItem(node)
                }
            case .workspace(let workspace):
                store?.selectWorkspace(workspace)
                if modifierFlags.contains(.option) {
                    store?.createSession(in: workspace)
                }
            case .branch(let workspace, _, _):
                store?.selectWorkspace(workspace)
            case .worktree(let workspace, let worktree):
                if modifierFlags.contains(.option) {
                    store?.createSession(in: workspace, for: worktree)
                } else if workspace.supportsRepositoryFeatures {
                    store?.requestSwitchToWorktree(worktree, in: workspace)
                } else {
                    store?.selectWorkspace(workspace)
                }
            }
        }

        private func selectedWorktrees(from nodes: [SidebarNodeItem]) -> (WorkspaceModel, [WorktreeModel])? {
            guard let workspace = nodes.compactMap(\.workspace).first,
                  nodes.allSatisfy({ $0.workspace?.id == workspace.id }) else {
                return nil
            }

            let orderedUnique = nodes
                .flatMap(\.representedWorktrees)
                .reduce(into: [String: WorktreeModel]()) { result, worktree in
                    result[worktree.path] = worktree
                }
                .values
                .sorted { $0.path < $1.path }

            guard !orderedUnique.isEmpty else { return nil }
            return (workspace, orderedUnique)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? SidebarNodeItem)?.children.count ?? rootNodes.count
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? SidebarNodeItem)?.isExpandable ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            let nodes = (item as? SidebarNodeItem)?.children ?? rootNodes
            return nodes[index]
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? SidebarNodeItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("WorkspaceOutlineCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarOutlineCellView ?? SidebarOutlineCellView()
            cell.identifier = identifier
            let row = outlineView.row(forItem: node)
            let isSelected = row >= 0 && outlineView.selectedRowIndexes.contains(row)
            cell.apply(node: node, store: store, isSelected: isSelected)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            SidebarOutlineRowView()
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let node = item as? SidebarNodeItem else { return 48 }
            switch node.kind {
            case .group, .archiveGroup:
                return 32
            case .workspace:
                return 36
            case .branch:
                return 18
            case .worktree:
                return 26
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let outlineView = notification.object as? NSOutlineView else { return }

            let rowIndexes = IndexSet(integersIn: 0..<outlineView.numberOfRows)
            if !rowIndexes.isEmpty {
                outlineView.reloadData(forRowIndexes: rowIndexes, columnIndexes: IndexSet(integer: 0))
            }

            let nodes = selectedNodes(from: outlineView)
            guard nodes.count == 1, let node = nodes.first else { return }

            switch node.kind {
            case .group, .archiveGroup:
                pinnedSelectionNodeID = node.id
                suppressSelectionSync = true
                isUserDrivenSelection = true
            case .workspace(let workspace):
                pinnedSelectionNodeID = node.id
                suppressSelectionSync = false
                store?.selectWorkspace(workspace)
            case .branch(let workspace, _, _):
                pinnedSelectionNodeID = nil
                suppressSelectionSync = false
                store?.selectWorkspace(workspace)
            case .worktree(let workspace, let worktree):
                pinnedSelectionNodeID = node.id
                isUserDrivenSelection = true
                store?.selectWorkspace(workspace)
                if workspace.supportsRepositoryFeatures {
                    store?.requestSwitchToWorktree(worktree, in: workspace)
                }
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isRestoringExpansion,
                  let node = notification.userInfo?["NSObject"] as? SidebarNodeItem else { return }
            switch node.kind {
            case .group(let group):
                store?.setWorkspaceGroupExpanded(group.id, isExpanded: true)
            case .archiveGroup:
                if store?.appSettings.showArchivedWorkspaces != true {
                    store?.dispatch(.toggleShowArchived)
                }
            case .workspace(let workspace):
                if !workspace.isSidebarExpanded {
                    workspace.isSidebarExpanded = true
                    store?.persist()
                }
            default:
                break
            }
            container?.relayout()
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isRestoringExpansion,
                  let node = notification.userInfo?["NSObject"] as? SidebarNodeItem else { return }
            switch node.kind {
            case .group(let group):
                store?.setWorkspaceGroupExpanded(group.id, isExpanded: false)
            case .archiveGroup:
                if store?.appSettings.showArchivedWorkspaces != false {
                    store?.dispatch(.toggleShowArchived)
                }
            case .workspace(let workspace):
                if workspace.isSidebarExpanded {
                    workspace.isSidebarExpanded = false
                    store?.persist()
                }
            default:
                break
            }
            container?.relayout()
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? SidebarNodeItem else { return nil }

            if let group = node.groupModel {
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(group.id.uuidString, forType: Self.groupDragType)
                return pasteboardItem
            }

            guard node.isWorkspaceNode, let workspace = node.workspace else {
                return nil
            }

            let selectedWorkspaceIDs = selectedNodes(from: outlineView)
                .filter(\.isWorkspaceNode)
                .compactMap(\.workspace?.id)

            let draggedWorkspaceIDs: [UUID]
            if selectedWorkspaceIDs.contains(workspace.id) {
                draggedWorkspaceIDs = selectedWorkspaceIDs
            } else {
                draggedWorkspaceIDs = [workspace.id]
            }

            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(
                draggedWorkspaceIDs.map(\.uuidString).joined(separator: "\n"),
                forType: Self.workspaceDragType
            )
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            let isGroupDrag = info.draggingPasteboard.string(forType: Self.groupDragType) != nil

            if isGroupDrag {
                if item == nil { return .move }
                // Hovering ON a node — retarget to the root-level gap after it
                if let targetIndex = rootInsertionIndex(for: item, in: outlineView) {
                    outlineView.setDropItem(nil, dropChildIndex: targetIndex)
                    return .move
                }
                return []
            }

            // Workspace drag
            if let node = item as? SidebarNodeItem, (node.isGroupNode || node.isArchiveGroupNode) {
                return .move
            }
            if item == nil { return .move }
            // Hovering ON a non-group node — retarget to root-level gap
            if let targetIndex = rootInsertionIndex(for: item, in: outlineView) {
                outlineView.setDropItem(nil, dropChildIndex: targetIndex)
                return .move
            }
            return []
        }

        /// Find the root-level insertion index when hovering on a node.
        /// Returns the index *after* the hovered node's root-level ancestor.
        private func rootInsertionIndex(for item: Any?, in outlineView: NSOutlineView) -> Int? {
            guard let node = item as? SidebarNodeItem else { return nil }
            let rootCount = outlineView.numberOfChildren(ofItem: nil)
            // Check if the node is itself a root item
            for i in 0..<rootCount {
                if outlineView.child(i, ofItem: nil) as AnyObject === node {
                    return i + 1
                }
            }
            // The node is a child of a root item — find the parent's root index
            if let parent = outlineView.parent(forItem: node) as AnyObject? {
                for i in 0..<rootCount {
                    if outlineView.child(i, ofItem: nil) as AnyObject === parent {
                        return i + 1
                    }
                }
            }
            return nil
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            if let groupIDString = info.draggingPasteboard.string(forType: Self.groupDragType),
               let groupID = UUID(uuidString: groupIDString) {
                guard item == nil else { return false }
                let rootOrder = store?.effectiveSidebarRootOrder() ?? []
                let targetIndex = index == -1 ? rootOrder.count : index
                store?.moveSidebarRootItem(.group(groupID), toIndex: targetIndex)
                return true
            }

            guard let payload = info.draggingPasteboard.string(forType: Self.workspaceDragType) else {
                return false
            }

            let ids = payload
                .split(whereSeparator: \.isNewline)
                .compactMap { UUID(uuidString: String($0)) }
            guard !ids.isEmpty else { return false }

            if let node = item as? SidebarNodeItem, node.isArchiveGroupNode {
                store?.setWorkspacesArchived(ids, archived: true)
                return true
            }

            if let node = item as? SidebarNodeItem, let group = node.groupModel {
                // Unarchive if needed before moving into a group
                store?.setWorkspacesArchived(ids, archived: false)
                store?.moveWorkspacesIntoGroup(ids: ids, groupID: group.id, atIndex: index == -1 ? group.workspaceIDs.count : index)
                return true
            }

            // Moving workspace(s) to root level — unarchive if needed
            store?.setWorkspacesArchived(ids, archived: false)
            store?.removeWorkspacesFromAllGroups(ids: ids)
            let rootOrder = store?.effectiveSidebarRootOrder() ?? []
            let targetIndex = index == -1 ? rootOrder.count : index
            store?.moveSidebarRootItems(ids.map { .workspace($0) }, toIndex: targetIndex)
            return true
        }
}

private final class SidebarOutlineContainerView: NSView {
    let outlineView = SidebarOutlineView()
    private let scrollView = NSScrollView()
    private let contentView = SidebarScrollContentView()
    private let footerHostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.rowHeight = 46
        outlineView.indentationPerLevel = 10
        outlineView.floatsGroupRows = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.focusRingType = .none
        outlineView.backgroundColor = .clear
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.intercellSpacing = NSSize(width: 0, height: 4)
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask([], forLocal: false)
        outlineView.draggingDestinationFeedbackStyle = .gap

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        contentView.outlineView = outlineView
        scrollView.documentView = contentView
        addSubview(scrollView)

        footerHostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerHostingView)

        let footerSeparator = NSBox()
        footerSeparator.boxType = .separator
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerSeparator)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor),

            footerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerSeparator.bottomAnchor.constraint(equalTo: footerHostingView.topAnchor, constant: -4),

            footerHostingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            footerHostingView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            footerHostingView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            footerHostingView.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateContentLayout()
    }

    func reloadOutlineData() {
        outlineView.reloadData()
        updateContentLayout()
    }

    func setOpenRepositoryAction(_ action: @escaping () -> Void) {
        footerHostingView.rootView = AnyView(SidebarOpenRepositoryRow(action: action))
    }

    func relayout() {
        updateContentLayout()
    }

    private func updateContentLayout() {
        let visibleWidth = max(scrollView.contentSize.width, bounds.width)
        let visibleHeight = max(scrollView.contentSize.height, bounds.height)
        let outlineHeight = outlineContentHeight()
        contentView.outlineHeight = outlineHeight
        let requiredHeight = contentView.requiredHeight(forWidth: visibleWidth)
        contentView.frame = NSRect(
            x: 0,
            y: 0,
            width: visibleWidth,
            height: max(visibleHeight, requiredHeight)
        )
        contentView.needsLayout = true
    }

    private func outlineContentHeight() -> CGFloat {
        let rowCount = outlineView.numberOfRows
        guard rowCount > 0 else { return 0 }
        return ceil(outlineView.rect(ofRow: rowCount - 1).maxY)
    }
}

private final class SidebarScrollContentView: NSView {
    private enum Layout {
        static let topInset: CGFloat = 8
        static let bottomInset: CGFloat = 12
    }

    override var isFlipped: Bool {
        true
    }

    weak var outlineView: NSOutlineView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let outlineView, outlineView.superview !== self {
                addSubview(outlineView)
            }
        }
    }

    var outlineHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let width = bounds.width
        outlineView?.frame = NSRect(
            x: 0,
            y: Layout.topInset,
            width: width,
            height: outlineHeight
        )
    }

    func requiredHeight(forWidth _: CGFloat) -> CGFloat {
        Layout.topInset
            + outlineHeight
            + Layout.bottomInset
    }
}

private final class SidebarOutlineView: NSOutlineView {
    var menuProvider: ((Int) -> NSMenu?)?
    var activateSelection: ((NSEvent.ModifierFlags) -> Void)?
    var toggleExpansionForSelection: (() -> Void)?

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        frame.origin.x = 6
        frame.size.width = 12
        return frame
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        let item = self.item(atRow: row) as? SidebarNodeItem
        let isExpandable = item?.isExpandable ?? false
        let isTopLevel = item?.isWorkspaceNode ?? false
        let disclosureEnd: CGFloat = 20
        if !isExpandable {
            frame.origin.x = disclosureEnd
            frame.size.width = bounds.width - disclosureEnd - 8
        } else {
            let shift = frame.origin.x - disclosureEnd
            if shift > 0 {
                frame.origin.x -= shift
                frame.size.width += shift
            }
        }
        return frame
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        return menuProvider?(row)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            activateSelection?(event.modifierFlags)
        case 49:
            toggleExpansionForSelection?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class SidebarOutlineRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        LineyTheme.sidebarSelectionFill.setFill()
        path.fill()
        LineyTheme.sidebarSelectionStroke.setStroke()
        path.lineWidth = 1.25
        path.stroke()
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

private final class SidebarOutlineCellView: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    func apply(node: SidebarNodeItem, store: WorkspaceStore?, isSelected: Bool) {
        let rootView = AnyView(
            SidebarNodeRow(node: node, store: store, isSelected: isSelected)
                .transaction { $0.animation = nil }
        )
        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.hostingView = hostingView
        }
    }
}

private struct SidebarNodeRow: View {
    let node: SidebarNodeItem
    let store: WorkspaceStore?
    let isSelected: Bool

    var body: some View {
        switch node.kind {
        case .group(let group):
            GroupRowContent(group: group, childCount: node.children.count, store: store, isSelected: isSelected)
        case .archiveGroup:
            ArchiveGroupRowContent(childCount: node.children.count, store: store)
        case .workspace(let workspace):
            WorkspaceRowContent(workspace: workspace, store: store, isSelected: isSelected)
        case .branch:
            EmptyView()
        case .worktree(let workspace, let worktree):
            WorktreeRowContent(workspace: workspace, worktree: worktree, store: store, isSelected: isSelected)
        }
    }
}

private struct GroupRowContent: View {
    let group: WorkspaceGroup
    let childCount: Int
    let store: WorkspaceStore?
    let isSelected: Bool
    @State private var isHovering = false

    private var appSettings: AppSettings {
        store?.appSettings ?? AppSettings()
    }

    private var uiScale: CGFloat {
        CGFloat(appSettings.uiScale)
    }

    private var iconPalette: SidebarIconPaletteDescriptor {
        group.icon.palette.descriptor
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6 * uiScale) {
                Image(systemName: group.icon.symbolName)
                    .font(.system(size: 10 * uiScale, weight: .bold))
                    .foregroundStyle(iconPalette.foreground.opacity(0.85))

                Text(group.name)
                    .font(.system(size: 11 * uiScale, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? LineyTheme.tertiaryText : LineyTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text("\(childCount)")
                    .font(.system(size: 9 * uiScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText.opacity(0.7))
            }
            .padding(.vertical, 4 * uiScale)
            .padding(.leading, 2 * uiScale)
            .padding(.trailing, 8 * uiScale)

            Rectangle()
                .fill(LineyTheme.border.opacity(0.5))
                .frame(height: 0.5)
                .padding(.leading, 2 * uiScale)
                .padding(.trailing, 8 * uiScale)
        }
        .background(
            LineyTheme.subtleFill.opacity(isHovering ? 0.8 : 0),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onHover { isInside in
            isHovering = isInside
        }
    }
}

private struct ArchiveGroupRowContent: View {
    let childCount: Int
    let store: WorkspaceStore?

    private var uiScale: CGFloat {
        CGFloat(store?.appSettings.uiScale ?? 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6 * uiScale) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 10 * uiScale, weight: .bold))
                    .foregroundStyle(LineyTheme.mutedText.opacity(0.6))

                Text(LocalizationManager.shared.string("sidebar.archiveGroup.title"))
                    .font(.system(size: 11 * uiScale, weight: .bold, design: .rounded))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text("\(childCount)")
                    .font(.system(size: 9 * uiScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText.opacity(0.7))
            }
            .padding(.vertical, 4 * uiScale)
            .padding(.leading, 2 * uiScale)
            .padding(.trailing, 8 * uiScale)

            Rectangle()
                .fill(LineyTheme.border.opacity(0.5))
                .frame(height: 0.5)
                .padding(.leading, 2 * uiScale)
                .padding(.trailing, 8 * uiScale)
        }
    }
}

private struct WorkspaceRowContent: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject private var localization = LocalizationManager.shared
    let store: WorkspaceStore?
    let isSelected: Bool
    @State private var isHovering = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var appSettings: AppSettings {
        store?.appSettings ?? AppSettings()
    }

    private var icon: SidebarItemIcon {
        store?.sidebarIcon(for: workspace)
            ?? (workspace.supportsRepositoryFeatures ? .repositoryDefault : .localTerminalDefault)
    }

    private var uiScale: CGFloat {
        CGFloat(appSettings.uiScale)
    }

    private var iconActivityIndicator: SidebarIconActivityIndicator {
        if workspace.quitConfirmationSessionCount > 0 {
            return .working
        }
        if workspace.activeWorktreePath == workspace.repositoryRoot {
            return .current
        }
        return .none
    }

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            SidebarItemIconView(
                icon: icon,
                size: 22 * uiScale,
                activityIndicator: iconActivityIndicator,
                activityPalette: appSettings.sidebarActivityIndicatorPalette,
                isEmphasized: isSelected
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if appSettings.sidebarShowsSecondaryLabels {
                    Text(workspace.supportsRepositoryFeatures ? workspace.currentBranch : workspace.activeWorktreePath.lastPathComponentValue)
                        .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if appSettings.sidebarShowsWorkspaceBadges {
                HStack(spacing: 6 * uiScale) {
                    if workspace.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9 * uiScale, weight: .bold))
                            .foregroundStyle(LineyTheme.accent)
                    }

                    if workspace.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 9 * uiScale, weight: .bold))
                            .foregroundStyle(LineyTheme.mutedText)
                    }

                    if workspace.activeSessionCount > 1 {
                        SidebarInfoBadge(text: "\(workspace.activeSessionCount)", tone: .neutral)
                    }

                    if workspace.supportsRepositoryFeatures, workspace.hasUncommittedChanges {
                        SidebarInfoBadge(text: "\(workspace.changedFileCount)", tone: .warning)
                    }

                    if workspace.supportsRepositoryFeatures,
                       workspace.aheadCount > 0 || workspace.behindCount > 0 {
                        SidebarInfoBadge(text: "↑\(workspace.aheadCount) ↓\(workspace.behindCount)", tone: .accent)
                    }

                    if !workspace.runScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SidebarInfoBadge(text: localized("sidebar.badge.run"), tone: .success)
                    }

                    if !workspace.workflows.isEmpty {
                        SidebarInfoBadge(text: localized("sidebar.badge.flow"), tone: .accent)
                    }
                }
            }
        }
        .padding(.vertical, 4 * uiScale)
        .padding(.leading, 2 * uiScale)
        .padding(.trailing, 8 * uiScale)
        .background(
            LineyTheme.subtleFill.opacity(isHovering ? 1 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onHover { isInside in
            isHovering = isInside
        }
    }
}

private struct WorktreeRowContent: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject private var localization = LocalizationManager.shared
    let worktree: WorktreeModel
    let store: WorkspaceStore?
    let isSelected: Bool
    @State private var isHovering = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var appSettings: AppSettings {
        store?.appSettings ?? AppSettings()
    }

    private var icon: SidebarItemIcon {
        store?.sidebarIcon(for: worktree, in: workspace) ?? .worktreeDefault
    }

    private var uiScale: CGFloat {
        CGFloat(appSettings.uiScale)
    }

    private var iconSize: CGFloat { 16 * uiScale }
    private var leadingInset: CGFloat { 5 * uiScale }
    private var iconColumnWidth: CGFloat { 24 * uiScale }
    private var iconActivityIndicator: SidebarIconActivityIndicator {
        if workspace.runningSessionCount(forWorktreePath: worktree.path) > 0 {
            return .working
        }
        if workspace.activeWorktreePath == worktree.path {
            return .current
        }
        return .none
    }

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            SidebarItemIconView(
                icon: icon,
                size: iconSize,
                usesCircularShape: true,
                activityIndicator: iconActivityIndicator,
                activityPalette: appSettings.sidebarActivityIndicatorPalette,
                isEmphasized: isSelected
            )
            .frame(width: iconColumnWidth, alignment: .leading)
            Text(worktree.displayName)
                .font(.system(size: 10 * uiScale, weight: .medium))
                .lineLimit(1)
            if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8 * uiScale))
                    .foregroundStyle(LineyTheme.mutedText)
            }
            Spacer()
            if appSettings.sidebarShowsWorktreeBadges {
                HStack(spacing: 5 * uiScale) {
                    if workspace.activeWorktreePath == worktree.path {
                        SidebarInfoBadge(text: localized("sidebar.badge.current"), tone: .subtleSuccess)
                    }

                    if let status = workspace.status(for: worktree.path),
                       status.hasUncommittedChanges {
                        SidebarInfoBadge(text: "\(status.changedFileCount)", tone: .warning)
                    }
                }
            }
        }
        .padding(.vertical, 1 * uiScale)
        .padding(.leading, leadingInset)
        .padding(.trailing, 8 * uiScale)
        .frame(maxWidth: .infinity, minHeight: 24 * uiScale, alignment: .leading)
        .background(
            LineyTheme.subtleFill.opacity(isHovering ? 1 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onHover { isInside in
            isHovering = isInside
        }
    }
}

struct SidebarItemIconView: View {
    let icon: SidebarItemIcon
    let size: CGFloat
    var usesCircularShape: Bool = false
    var activityIndicator: SidebarIconActivityIndicator = .none
    var activityPalette: SidebarIconPalette = .amber
    var isEmphasized: Bool = false

    private var palette: SidebarIconPaletteDescriptor {
        icon.palette.descriptor
    }

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(
            cornerRadius: usesCircularShape ? size / 2 : max(7, size * 0.34),
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: icon.symbolName)
                .font(.system(size: max(9, size * 0.48), weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(palette.foreground)
                .frame(width: size, height: size)
                .background(background)
                .overlay(
                    backgroundShape
                        .strokeBorder(palette.border, lineWidth: 1)
                )

            if activityIndicator == .working {
                SidebarIconActivityBadge(
                    kind: activityIndicator,
                    size: size,
                    palette: activityPalette,
                    isEmphasized: isEmphasized
                )
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size + 2, height: size + 2)
    }

    @ViewBuilder
    private var background: some View {
        switch icon.fillStyle {
        case .solid:
            backgroundShape.fill(palette.solidBackground)
        case .gradient:
            backgroundShape.fill(
                LinearGradient(
                    colors: [palette.gradientStart, palette.gradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

enum SidebarIconActivityIndicator {
    case none
    case current
    case working
}

struct SidebarIconActivityBadge: View {
    let kind: SidebarIconActivityIndicator
    let size: CGFloat
    let palette: SidebarIconPalette
    let isEmphasized: Bool
    @State private var isAnimating = false

    private var activityColor: Color {
        palette.descriptor.gradientEnd
    }

    private var badgeSize: CGFloat {
        switch kind {
        case .working:
            return max(7, size * 0.34)
        case .current, .none:
            return max(6, size * 0.28)
        }
    }

    private var pulseLineWidth: CGFloat {
        isEmphasized ? 1.4 : 1.15
    }

    private var pulseOpacity: Double {
        isEmphasized ? 0.8 : 0.5
    }

    private var pulseScale: CGFloat {
        isEmphasized ? 2.15 : 1.85
    }

    private var pulseDuration: Double {
        isEmphasized ? 0.95 : 1.15
    }

    private var coreScale: CGFloat {
        guard kind == .working else { return 1 }
        return isAnimating ? 1.18 : 0.9
    }

    private var coreOpacity: Double {
        guard kind == .working else { return 1 }
        return isAnimating ? 1 : 0.82
    }

    private var glowRadius: CGFloat {
        guard kind == .working else { return 0 }
        return isEmphasized ? 6 : 4
    }

    var body: some View {
        ZStack {
            if kind == .working {
                Circle()
                    .fill(activityColor.opacity(isAnimating ? 0.18 : 0.06))
                    .frame(width: badgeSize, height: badgeSize)
                    .scaleEffect(isAnimating ? pulseScale * 0.9 : 1.0)
                    .blur(radius: isEmphasized ? 1.2 : 0.8)

                Circle()
                    .stroke(activityColor.opacity(pulseOpacity), lineWidth: pulseLineWidth)
                    .frame(width: badgeSize, height: badgeSize)
                    .scaleEffect(isAnimating ? pulseScale : 1.0)
                    .opacity(isAnimating ? 0 : pulseOpacity)
            }

            Circle()
                .fill(activityColor)
                .frame(width: badgeSize, height: badgeSize)
                .overlay(Circle().stroke(LineyTheme.sidebarBackground, lineWidth: 1))
                .scaleEffect(coreScale)
                .opacity(coreOpacity)
                .shadow(color: activityColor.opacity(kind == .working ? 0.9 : 0), radius: glowRadius)
        }
        .onAppear {
            updateAnimationState()
        }
        .onChange(of: kind) { _, _ in
            updateAnimationState()
        }
    }

    private func updateAnimationState() {
        guard kind == .working else {
            isAnimating = false
            return
        }
        isAnimating = false
        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
            isAnimating = true
        }
    }
}

struct SidebarIconPaletteDescriptor {
    let foreground: Color
    let solidBackground: Color
    let gradientStart: Color
    let gradientEnd: Color
    let border: Color
}

extension SidebarIconPalette {
    var descriptor: SidebarIconPaletteDescriptor {
        switch self {
        case .blue:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.55, green: 0.76, blue: 1.0),
                solidBackground: Color(red: 0.09, green: 0.18, blue: 0.31),
                gradientStart: Color(red: 0.14, green: 0.30, blue: 0.58),
                gradientEnd: Color(red: 0.11, green: 0.55, blue: 0.80),
                border: Color(red: 0.30, green: 0.48, blue: 0.72)
            )
        case .cyan:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.78, green: 0.98, blue: 1.0),
                solidBackground: Color(red: 0.06, green: 0.21, blue: 0.28),
                gradientStart: Color(red: 0.06, green: 0.37, blue: 0.50),
                gradientEnd: Color(red: 0.10, green: 0.67, blue: 0.78),
                border: Color(red: 0.24, green: 0.58, blue: 0.67)
            )
        case .aqua:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.84, green: 1.0, blue: 0.98),
                solidBackground: Color(red: 0.05, green: 0.22, blue: 0.24),
                gradientStart: Color(red: 0.05, green: 0.40, blue: 0.41),
                gradientEnd: Color(red: 0.12, green: 0.73, blue: 0.67),
                border: Color(red: 0.24, green: 0.63, blue: 0.58)
            )
        case .ice:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.91, green: 0.98, blue: 1.0),
                solidBackground: Color(red: 0.12, green: 0.18, blue: 0.24),
                gradientStart: Color(red: 0.19, green: 0.30, blue: 0.42),
                gradientEnd: Color(red: 0.37, green: 0.57, blue: 0.72),
                border: Color(red: 0.41, green: 0.57, blue: 0.69)
            )
        case .sky:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.86, green: 0.95, blue: 1.0),
                solidBackground: Color(red: 0.10, green: 0.19, blue: 0.29),
                gradientStart: Color(red: 0.16, green: 0.31, blue: 0.56),
                gradientEnd: Color(red: 0.28, green: 0.56, blue: 0.87),
                border: Color(red: 0.35, green: 0.52, blue: 0.75)
            )
        case .teal:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.73, green: 0.96, blue: 0.95),
                solidBackground: Color(red: 0.07, green: 0.24, blue: 0.24),
                gradientStart: Color(red: 0.07, green: 0.39, blue: 0.42),
                gradientEnd: Color(red: 0.11, green: 0.63, blue: 0.61),
                border: Color(red: 0.26, green: 0.58, blue: 0.55)
            )
        case .turquoise:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.77, green: 0.98, blue: 0.96),
                solidBackground: Color(red: 0.06, green: 0.22, blue: 0.20),
                gradientStart: Color(red: 0.08, green: 0.40, blue: 0.35),
                gradientEnd: Color(red: 0.13, green: 0.71, blue: 0.58),
                border: Color(red: 0.24, green: 0.62, blue: 0.52)
            )
        case .mint:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.83, green: 0.99, blue: 0.91),
                solidBackground: Color(red: 0.08, green: 0.25, blue: 0.18),
                gradientStart: Color(red: 0.11, green: 0.42, blue: 0.28),
                gradientEnd: Color(red: 0.17, green: 0.66, blue: 0.44),
                border: Color(red: 0.30, green: 0.58, blue: 0.41)
            )
        case .green:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.89, green: 0.98, blue: 0.84),
                solidBackground: Color(red: 0.16, green: 0.24, blue: 0.09),
                gradientStart: Color(red: 0.24, green: 0.42, blue: 0.10),
                gradientEnd: Color(red: 0.43, green: 0.66, blue: 0.18),
                border: Color(red: 0.46, green: 0.62, blue: 0.24)
            )
        case .forest:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.88, green: 0.98, blue: 0.85),
                solidBackground: Color(red: 0.10, green: 0.20, blue: 0.09),
                gradientStart: Color(red: 0.15, green: 0.33, blue: 0.10),
                gradientEnd: Color(red: 0.24, green: 0.52, blue: 0.17),
                border: Color(red: 0.31, green: 0.48, blue: 0.22)
            )
        case .lime:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.94, green: 1.0, blue: 0.80),
                solidBackground: Color(red: 0.20, green: 0.24, blue: 0.08),
                gradientStart: Color(red: 0.32, green: 0.43, blue: 0.10),
                gradientEnd: Color(red: 0.56, green: 0.73, blue: 0.17),
                border: Color(red: 0.52, green: 0.64, blue: 0.22)
            )
        case .olive:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.92, green: 0.96, blue: 0.78),
                solidBackground: Color(red: 0.22, green: 0.23, blue: 0.10),
                gradientStart: Color(red: 0.34, green: 0.37, blue: 0.12),
                gradientEnd: Color(red: 0.50, green: 0.57, blue: 0.20),
                border: Color(red: 0.49, green: 0.54, blue: 0.23)
            )
        case .gold:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.95, blue: 0.76),
                solidBackground: Color(red: 0.31, green: 0.24, blue: 0.09),
                gradientStart: Color(red: 0.55, green: 0.37, blue: 0.07),
                gradientEnd: Color(red: 0.85, green: 0.63, blue: 0.15),
                border: Color(red: 0.68, green: 0.50, blue: 0.20)
            )
        case .sand:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.95, blue: 0.86),
                solidBackground: Color(red: 0.27, green: 0.22, blue: 0.14),
                gradientStart: Color(red: 0.45, green: 0.33, blue: 0.18),
                gradientEnd: Color(red: 0.69, green: 0.54, blue: 0.31),
                border: Color(red: 0.60, green: 0.49, blue: 0.31)
            )
        case .bronze:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.91, blue: 0.79),
                solidBackground: Color(red: 0.28, green: 0.17, blue: 0.10),
                gradientStart: Color(red: 0.47, green: 0.24, blue: 0.12),
                gradientEnd: Color(red: 0.72, green: 0.41, blue: 0.21),
                border: Color(red: 0.61, green: 0.36, blue: 0.20)
            )
        case .amber:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.93, blue: 0.76),
                solidBackground: Color(red: 0.34, green: 0.20, blue: 0.06),
                gradientStart: Color(red: 0.62, green: 0.34, blue: 0.05),
                gradientEnd: Color(red: 0.91, green: 0.56, blue: 0.10),
                border: Color(red: 0.76, green: 0.46, blue: 0.16)
            )
        case .orange:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.90, blue: 0.78),
                solidBackground: Color(red: 0.34, green: 0.17, blue: 0.08),
                gradientStart: Color(red: 0.62, green: 0.25, blue: 0.07),
                gradientEnd: Color(red: 0.87, green: 0.46, blue: 0.12),
                border: Color(red: 0.72, green: 0.38, blue: 0.17)
            )
        case .copper:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.88, blue: 0.79),
                solidBackground: Color(red: 0.33, green: 0.15, blue: 0.09),
                gradientStart: Color(red: 0.59, green: 0.23, blue: 0.11),
                gradientEnd: Color(red: 0.80, green: 0.37, blue: 0.19),
                border: Color(red: 0.69, green: 0.31, blue: 0.18)
            )
        case .rust:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.99, green: 0.87, blue: 0.81),
                solidBackground: Color(red: 0.29, green: 0.12, blue: 0.09),
                gradientStart: Color(red: 0.47, green: 0.18, blue: 0.12),
                gradientEnd: Color(red: 0.65, green: 0.25, blue: 0.17),
                border: Color(red: 0.56, green: 0.23, blue: 0.17)
            )
        case .coral:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.86, blue: 0.83),
                solidBackground: Color(red: 0.33, green: 0.12, blue: 0.12),
                gradientStart: Color(red: 0.60, green: 0.18, blue: 0.19),
                gradientEnd: Color(red: 0.84, green: 0.33, blue: 0.29),
                border: Color(red: 0.69, green: 0.29, blue: 0.28)
            )
        case .peach:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.91, blue: 0.84),
                solidBackground: Color(red: 0.31, green: 0.15, blue: 0.12),
                gradientStart: Color(red: 0.55, green: 0.22, blue: 0.17),
                gradientEnd: Color(red: 0.86, green: 0.45, blue: 0.31),
                border: Color(red: 0.71, green: 0.37, blue: 0.28)
            )
        case .brick:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.99, green: 0.87, blue: 0.80),
                solidBackground: Color(red: 0.30, green: 0.11, blue: 0.08),
                gradientStart: Color(red: 0.50, green: 0.16, blue: 0.10),
                gradientEnd: Color(red: 0.73, green: 0.26, blue: 0.16),
                border: Color(red: 0.61, green: 0.24, blue: 0.17)
            )
        case .crimson:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.85, blue: 0.88),
                solidBackground: Color(red: 0.29, green: 0.08, blue: 0.12),
                gradientStart: Color(red: 0.48, green: 0.10, blue: 0.18),
                gradientEnd: Color(red: 0.74, green: 0.16, blue: 0.31),
                border: Color(red: 0.62, green: 0.18, blue: 0.29)
            )
        case .ruby:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.84, blue: 0.87),
                solidBackground: Color(red: 0.30, green: 0.07, blue: 0.10),
                gradientStart: Color(red: 0.53, green: 0.10, blue: 0.16),
                gradientEnd: Color(red: 0.80, green: 0.17, blue: 0.25),
                border: Color(red: 0.67, green: 0.19, blue: 0.25)
            )
        case .berry:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.99, green: 0.86, blue: 0.93),
                solidBackground: Color(red: 0.28, green: 0.09, blue: 0.20),
                gradientStart: Color(red: 0.46, green: 0.12, blue: 0.31),
                gradientEnd: Color(red: 0.67, green: 0.19, blue: 0.47),
                border: Color(red: 0.57, green: 0.21, blue: 0.42)
            )
        case .rose:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 1.0, green: 0.86, blue: 0.92),
                solidBackground: Color(red: 0.29, green: 0.11, blue: 0.18),
                gradientStart: Color(red: 0.50, green: 0.16, blue: 0.30),
                gradientEnd: Color(red: 0.77, green: 0.26, blue: 0.45),
                border: Color(red: 0.62, green: 0.26, blue: 0.40)
            )
        case .magenta:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.97, green: 0.86, blue: 1.0),
                solidBackground: Color(red: 0.22, green: 0.10, blue: 0.27),
                gradientStart: Color(red: 0.40, green: 0.15, blue: 0.53),
                gradientEnd: Color(red: 0.63, green: 0.20, blue: 0.75),
                border: Color(red: 0.52, green: 0.25, blue: 0.68)
            )
        case .orchid:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.98, green: 0.88, blue: 1.0),
                solidBackground: Color(red: 0.23, green: 0.11, blue: 0.31),
                gradientStart: Color(red: 0.39, green: 0.17, blue: 0.52),
                gradientEnd: Color(red: 0.62, green: 0.27, blue: 0.77),
                border: Color(red: 0.54, green: 0.29, blue: 0.67)
            )
        case .indigo:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.88, green: 0.89, blue: 1.0),
                solidBackground: Color(red: 0.14, green: 0.12, blue: 0.31),
                gradientStart: Color(red: 0.23, green: 0.18, blue: 0.57),
                gradientEnd: Color(red: 0.38, green: 0.29, blue: 0.81),
                border: Color(red: 0.40, green: 0.31, blue: 0.73)
            )
        case .navy:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.85, green: 0.89, blue: 1.0),
                solidBackground: Color(red: 0.08, green: 0.11, blue: 0.24),
                gradientStart: Color(red: 0.12, green: 0.17, blue: 0.45),
                gradientEnd: Color(red: 0.20, green: 0.28, blue: 0.68),
                border: Color(red: 0.24, green: 0.31, blue: 0.58)
            )
        case .steel:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.88, green: 0.93, blue: 0.98),
                solidBackground: Color(red: 0.12, green: 0.16, blue: 0.21),
                gradientStart: Color(red: 0.18, green: 0.24, blue: 0.33),
                gradientEnd: Color(red: 0.30, green: 0.39, blue: 0.51),
                border: Color(red: 0.36, green: 0.44, blue: 0.57)
            )
        case .violet:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.95, green: 0.89, blue: 1.0),
                solidBackground: Color(red: 0.21, green: 0.11, blue: 0.33),
                gradientStart: Color(red: 0.36, green: 0.17, blue: 0.59),
                gradientEnd: Color(red: 0.56, green: 0.25, blue: 0.84),
                border: Color(red: 0.50, green: 0.26, blue: 0.72)
            )
        case .iris:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.92, green: 0.90, blue: 1.0),
                solidBackground: Color(red: 0.19, green: 0.13, blue: 0.34),
                gradientStart: Color(red: 0.30, green: 0.20, blue: 0.59),
                gradientEnd: Color(red: 0.47, green: 0.31, blue: 0.86),
                border: Color(red: 0.46, green: 0.33, blue: 0.73)
            )
        case .lavender:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.97, green: 0.92, blue: 1.0),
                solidBackground: Color(red: 0.25, green: 0.18, blue: 0.35),
                gradientStart: Color(red: 0.41, green: 0.28, blue: 0.58),
                gradientEnd: Color(red: 0.63, green: 0.48, blue: 0.82),
                border: Color(red: 0.57, green: 0.45, blue: 0.72)
            )
        case .plum:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.97, green: 0.88, blue: 0.98),
                solidBackground: Color(red: 0.25, green: 0.10, blue: 0.25),
                gradientStart: Color(red: 0.41, green: 0.14, blue: 0.44),
                gradientEnd: Color(red: 0.61, green: 0.22, blue: 0.60),
                border: Color(red: 0.54, green: 0.24, blue: 0.53)
            )
        case .slate:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.88, green: 0.91, blue: 0.96),
                solidBackground: Color(red: 0.14, green: 0.17, blue: 0.23),
                gradientStart: Color(red: 0.22, green: 0.26, blue: 0.36),
                gradientEnd: Color(red: 0.31, green: 0.37, blue: 0.47),
                border: Color(red: 0.36, green: 0.42, blue: 0.54)
            )
        case .smoke:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.92, green: 0.94, blue: 0.97),
                solidBackground: Color(red: 0.18, green: 0.19, blue: 0.22),
                gradientStart: Color(red: 0.27, green: 0.29, blue: 0.33),
                gradientEnd: Color(red: 0.41, green: 0.43, blue: 0.49),
                border: Color(red: 0.45, green: 0.47, blue: 0.53)
            )
        case .charcoal:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.93, green: 0.93, blue: 0.95),
                solidBackground: Color(red: 0.08, green: 0.09, blue: 0.11),
                gradientStart: Color(red: 0.12, green: 0.14, blue: 0.17),
                gradientEnd: Color(red: 0.20, green: 0.22, blue: 0.26),
                border: Color(red: 0.27, green: 0.29, blue: 0.34)
            )
        case .graphite:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.92, green: 0.93, blue: 0.95),
                solidBackground: Color(red: 0.10, green: 0.11, blue: 0.14),
                gradientStart: Color(red: 0.16, green: 0.18, blue: 0.22),
                gradientEnd: Color(red: 0.28, green: 0.30, blue: 0.35),
                border: Color(red: 0.34, green: 0.36, blue: 0.41)
            )
        case .mocha:
            return SidebarIconPaletteDescriptor(
                foreground: Color(red: 0.96, green: 0.91, blue: 0.87),
                solidBackground: Color(red: 0.19, green: 0.13, blue: 0.11),
                gradientStart: Color(red: 0.31, green: 0.20, blue: 0.16),
                gradientEnd: Color(red: 0.46, green: 0.31, blue: 0.24),
                border: Color(red: 0.47, green: 0.33, blue: 0.28)
            )
        }
    }
}

private struct SidebarInfoBadge: View {
    enum Tone {
        case neutral
        case accent
        case success
        case subtleSuccess
        case warning
    }

    let text: String
    let tone: Tone

    private var foreground: Color {
        switch tone {
        case .neutral:
            return LineyTheme.mutedText
        case .accent:
            return LineyTheme.accent
        case .success:
            return LineyTheme.success
        case .subtleSuccess:
            return LineyTheme.success.opacity(0.82)
        case .warning:
            return LineyTheme.warning
        }
    }

    private var background: Color {
        switch tone {
        case .subtleSuccess:
            return LineyTheme.success.opacity(0.08)
        default:
            return LineyTheme.subtleFill
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
    }
}

private struct WorkspaceInlineActions: View {
    @ObservedObject var workspace: WorkspaceModel
    let store: WorkspaceStore?
    let isHovering: Bool

    var body: some View {
        if isHovering, let store {
            HStack(spacing: 6) {
                SidebarInlineIconButton(systemName: "plus.square.on.square") {
                    store.createSession(in: workspace)
                }
                if workspace.supportsRepositoryFeatures {
                    SidebarInlineIconButton(systemName: "plus.rectangle.on.folder") {
                        store.presentCreateWorktree(for: workspace)
                    }
                    SidebarInlineIconButton(systemName: "arrow.clockwise") {
                        store.refresh(workspace)
                    }
                }
            }
        }
    }
}

private struct WorktreeInlineActions: View {
    @ObservedObject var workspace: WorkspaceModel
    let worktree: WorktreeModel
    let store: WorkspaceStore?
    let isHovering: Bool

    var body: some View {
        if isHovering, let store {
            HStack(spacing: 6) {
                if workspace.supportsRepositoryFeatures, workspace.activeWorktreePath != worktree.path {
                    SidebarInlineIconButton(systemName: "arrow.right.circle") {
                        store.requestSwitchToWorktree(worktree, in: workspace)
                    }
                }
                SidebarInlineIconButton(systemName: "plus.square.on.square") {
                    store.createSession(in: workspace, for: worktree)
                }
                SidebarInlineIconButton(systemName: "rectangle.split.2x1") {
                    store.split(in: workspace, for: worktree, axis: .vertical)
                }
            }
        }
    }
}

private struct SidebarInlineIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LineyTheme.secondaryText)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SidebarActionWorktree {
    let workspaceID: UUID
    let worktreePath: String
}

private struct SidebarActionWorktreeBatch {
    let workspaceID: UUID
    let worktreePaths: [String]
}

private struct SidebarActionWorkflow {
    let workspaceID: UUID
    let workflowID: UUID
}

private struct SidebarActionMoveToGroup {
    let workspaceIDs: [UUID]
    let groupID: UUID
}

@MainActor
private final class SidebarNodeItem: NSObject {
    enum Kind {
        case group(WorkspaceGroup)
        case archiveGroup
        case workspace(WorkspaceModel)
        case branch(workspace: WorkspaceModel, label: String, worktrees: [WorktreeModel])
        case worktree(workspace: WorkspaceModel, worktree: WorktreeModel)
    }

    let id: String
    let kind: Kind
    let children: [SidebarNodeItem]

    static func group(group: WorkspaceGroup, children: [SidebarNodeItem]) -> SidebarNodeItem {
        SidebarNodeItem(
            id: "group:\(group.id.uuidString)",
            kind: .group(group),
            children: children
        )
    }

    static func archiveGroup(children: [SidebarNodeItem]) -> SidebarNodeItem {
        SidebarNodeItem(
            id: "archiveGroup",
            kind: .archiveGroup,
            children: children
        )
    }

    static func workspace(workspace: WorkspaceModel, children: [SidebarNodeItem]) -> SidebarNodeItem {
        SidebarNodeItem(
            id: "workspace:\(workspace.id.uuidString)",
            kind: .workspace(workspace),
            children: children
        )
    }

    static func branch(workspace: WorkspaceModel, label: String, children: [SidebarNodeItem]) -> SidebarNodeItem {
        SidebarNodeItem(
            id: "branch:\(workspace.id.uuidString):\(label)",
            kind: .branch(workspace: workspace, label: label, worktrees: children.compactMap(\.worktree)),
            children: children
        )
    }

    static func worktree(workspace: WorkspaceModel, worktree: WorktreeModel) -> SidebarNodeItem {
        SidebarNodeItem(
            id: "worktree:\(workspace.id.uuidString):\(worktree.path)",
            kind: .worktree(workspace: workspace, worktree: worktree),
            children: []
        )
    }

    init(id: String, kind: Kind, children: [SidebarNodeItem]) {
        self.id = id
        self.kind = kind
        self.children = children
        super.init()
    }

    var isExpandable: Bool {
        !children.isEmpty
    }

    var isGroupNode: Bool {
        if case .group = kind { return true }
        return false
    }

    var isArchiveGroupNode: Bool {
        if case .archiveGroup = kind { return true }
        return false
    }

    var isWorkspaceNode: Bool {
        if case .workspace = kind {
            return true
        }
        return false
    }

    var groupModel: WorkspaceGroup? {
        guard case .group(let group) = kind else { return nil }
        return group
    }

    var workspace: WorkspaceModel? {
        switch kind {
        case .group, .archiveGroup:
            return nil
        case .workspace(let workspace):
            return workspace
        case .branch(let workspace, _, _):
            return workspace
        case .worktree(let workspace, _):
            return workspace
        }
    }

    var worktree: WorktreeModel? {
        guard case .worktree(_, let worktree) = kind else { return nil }
        return worktree
    }

    var path: String? {
        switch kind {
        case .group, .archiveGroup:
            return nil
        case .workspace(let workspace):
            return workspace.activeWorktreePath
        case .branch:
            return nil
        case .worktree(_, let worktree):
            return worktree.path
        }
    }

    var representedWorktrees: [WorktreeModel] {
        switch kind {
        case .group, .archiveGroup:
            return []
        case .workspace:
            return []
        case .branch(_, _, let worktrees):
            return worktrees
        case .worktree(_, let worktree):
            return [worktree]
        }
    }

    func flattened() -> [SidebarNodeItem] {
        [self] + children.flatMap { $0.flattened() }
    }
}

private extension WorkspaceModel {
    func matchesSidebarQuery(_ query: String) -> Bool {
        name.lowercased().contains(query)
            || repositoryRoot.lowercased().contains(query)
            || currentBranch.lowercased().contains(query)
            || worktrees.contains { $0.matchesSidebarQuery(query) }
    }
}

private extension WorktreeModel {
    func matchesSidebarQuery(_ query: String) -> Bool {
        displayName.lowercased().contains(query)
            || path.lowercased().contains(query)
            || branchLabel.lowercased().contains(query)
            || head.lowercased().contains(query)
    }
}
