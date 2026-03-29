//
//  OverviewView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)]
    private var model: OverviewViewModel { OverviewViewModel(workspaces: store.workspaces) }

    private var uiScale: CGFloat {
        CGFloat(store.appSettings.uiScale)
    }

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(spacing: 0) {
            overviewHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OverviewSummaryCards(
                        totalWorkspaces: model.totalWorkspaces,
                        dirtyRepositories: model.dirtyRepositories,
                        failingPullRequests: model.failingPullRequests,
                        activeSessions: model.totalSessions
                    )

                    if !model.workflowLaunchers.isEmpty {
                        OverviewWorkflowStrip(items: model.workflowLaunchers) { item in
                            store.dispatch(.runWorkflow(item.workspaceID, item.workflowID))
                        }
                    }

                    if !model.recentActivities.isEmpty {
                        OverviewTimelinePanel(
                            items: model.recentActivities,
                            onOpenWorkspace: openWorkspace,
                            onClear: store.clearTimeline,
                            onReplay: { item in
                                store.replayActivity(workspaceID: item.workspace.id, activityID: item.entry.id)
                            }
                        )
                    }

                    if !model.worktreeRows.isEmpty {
                        OverviewWorktreePanel(
                            items: model.worktreeRows,
                            onOpenWorkspace: openWorkspace
                        )
                    }

                    if !model.todayFocusItems.isEmpty {
                        OverviewTodayFocusPanel(
                            items: model.todayFocusItems,
                            onOpenWorkspace: openWorkspace,
                            onAction: perform
                        )
                    }

                    if !model.executionCards.isEmpty || !model.waitingCards.isEmpty || !model.shippingCards.isEmpty {
                        OverviewTaskBoard(
                            executionCards: model.executionCards,
                            waitingCards: model.waitingCards,
                            shippingCards: model.shippingCards,
                            onOpenWorkspace: openWorkspace,
                            onAction: perform
                        )
                    }

                    if !model.pullRequestInboxSections.isEmpty {
                        OverviewPullRequestInboxPanel(
                            sections: model.pullRequestInboxSections,
                            readyTargets: model.readyPullRequestTargets,
                            behindTargets: model.behindPullRequestTargets,
                            releaseContextTargets: model.releaseContextTargets,
                            onOpenWorkspace: openWorkspace,
                            onAction: perform
                        )
                    }

                    if !model.blockerGroups.isEmpty {
                        OverviewBlockerPanel(
                            groups: model.blockerGroups,
                            onOpenWorkspace: openWorkspace,
                            onAction: perform
                        )
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.workspaces) { workspace in
                            DeskView(workspace: workspace) {
                                store.selectWorkspace(workspace)
                                onDismiss()
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineyTheme.appBackground)
        .scaleEffect(uiScale)
    }

    private var overviewHeader: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                Text(localized("main.overview.title"))
                    .font(.system(size: 16, weight: .bold))
                Text(localizedFormat("overview.header.sessionsAndDesksFormat", model.totalWorkspaces, model.totalSessions))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LineyTheme.mutedText)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LineyTheme.mutedText)
                    .frame(width: 24, height: 24)
                    .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(LineyTheme.sidebarBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LineyTheme.border).frame(height: 1)
        }
    }

    private func workspace(id: UUID) -> WorkspaceModel? {
        store.workspaces.first(where: { $0.id == id })
    }

    private func openWorkspace(_ workspaceID: UUID) {
        guard let workspace = workspace(id: workspaceID) else { return }
        store.selectWorkspace(workspace)
        onDismiss()
    }

    private func perform(_ action: OverviewWorkspaceAction) {
        switch action {
        case .openWorkspace(let workspaceID):
            if let workspace = workspace(id: workspaceID) {
                store.selectWorkspace(workspace)
                onDismiss()
            }
        case .runWorkflow(let workspaceID, let workflowID):
            store.dispatch(.runWorkflow(workspaceID, workflowID))
        case .openFailingCheck(let workspaceID, let worktreePath):
            store.dispatch(.openFailingCheckDetails(workspaceID, worktreePath))
        case .queuePullRequest(let workspaceID, let worktreePath):
            store.dispatch(.queuePullRequest(workspaceID, worktreePath))
        case .updatePullRequestBranch(let workspaceID, let worktreePath):
            store.dispatch(.updatePullRequestBranch(workspaceID, worktreePath))
        case .openPullRequest(let workspaceID, let worktreePath):
            store.dispatch(.openPullRequest(workspaceID, worktreePath))
        case .queuePullRequests(let targets):
            store.dispatch(.queuePullRequests(targets))
        case .updatePullRequestBranches(let targets):
            store.dispatch(.updatePullRequestBranches(targets))
        case .copyPullRequestReleaseNotesBatch(let targets):
            store.dispatch(.copyPullRequestReleaseNotesBatch(targets))
        }
    }
}

private struct OverviewSummaryCards: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let totalWorkspaces: Int
    let dirtyRepositories: Int
    let failingPullRequests: Int
    let activeSessions: Int

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        HStack(spacing: 14) {
            OverviewMetricCard(title: localized("overview.summary.workspaces"), value: "\(totalWorkspaces)", subtitle: localized("overview.summary.trackedDesks"), tone: .neutral)
            OverviewMetricCard(title: localized("overview.summary.dirty"), value: "\(dirtyRepositories)", subtitle: localized("overview.summary.repositories"), tone: .warning)
            OverviewMetricCard(title: localized("overview.summary.failing"), value: "\(failingPullRequests)", subtitle: localized("overview.summary.needAttention"), tone: .danger)
            OverviewMetricCard(title: localized("overview.summary.active"), value: "\(activeSessions)", subtitle: localized("overview.summary.runningSessions"), tone: .success)
        }
    }
}

private struct OverviewMetricCard: View {
    enum Tone {
        case neutral
        case success
        case warning
        case danger
    }

    let title: String
    let value: String
    let subtitle: String
    let tone: Tone

    private var accent: Color {
        switch tone {
        case .neutral:
            return LineyTheme.accent
        case .success:
            return LineyTheme.success
        case .warning:
            return LineyTheme.warning
        case .danger:
            return LineyTheme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(LineyTheme.mutedText)
            Text(value)
                .font(.system(size: 24, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LineyTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct OverviewWorkflowStrip: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let items: [OverviewWorkflowLauncher]
    let onRun: (OverviewWorkflowLauncher) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("overview.quickWorkflows"))
                .font(.system(size: 13, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            onRun(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.workflowName)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(item.workspaceName)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(LineyTheme.mutedText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct OverviewTimelinePanel: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let items: [OverviewTimelineItem]
    let onOpenWorkspace: (UUID) -> Void
    let onClear: () -> Void
    let onReplay: (OverviewTimelineItem) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("overview.timeline.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localized("overview.timeline.subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                Spacer()
                Button(localized("overview.timeline.clear"), action: onClear)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LineyTheme.danger)
                Text(localizedFormat("overview.timeline.recentCountFormat", items.count))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    OverviewTimelineRow(
                        item: item,
                        onOpenWorkspace: { onOpenWorkspace(item.workspace.id) },
                        onReplay: item.entry.replayAction == nil ? nil : { onReplay(item) }
                    )
                }
            }
        }
        .padding(14)
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct OverviewWorktreePanel: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let items: [OverviewWorktreeRow]
    let onOpenWorkspace: (UUID) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("overview.worktrees.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localized("overview.worktrees.subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                Spacer()
                Text(localizedFormat("overview.worktrees.countFormat", items.count))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            VStack(spacing: 8) {
                ForEach(items.prefix(8)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.isActive ? LineyTheme.accent : LineyTheme.border)
                            .frame(width: 6, height: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.worktree.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                if item.isActive {
                                    Text(localized("overview.worktrees.active"))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(LineyTheme.accent)
                                }
                                Spacer()
                                Button(item.workspace.name) {
                                    onOpenWorkspace(item.workspace.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(LineyTheme.accent)
                            }

                            Text(item.statusSummary)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(LineyTheme.secondaryText)

                            Text(item.worktree.path)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(LineyTheme.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct OverviewTodayFocusPanel: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let items: [OverviewFocusItem]
    let onOpenWorkspace: (UUID) -> Void
    let onAction: (OverviewWorkspaceAction) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("overview.todayFocus.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localized("overview.todayFocus.subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                Spacer()
                Text(localizedFormat("overview.todayFocus.activeCountFormat", items.count))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(LineyTheme.accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.headline)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button(item.actionLabel) {
                                    onAction(item.action)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(LineyTheme.accent)
                            }

                            Text(item.detail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(LineyTheme.secondaryText)

                            Button(item.workspace.name) {
                                onOpenWorkspace(item.workspace.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(LineyTheme.mutedText)
                        }
                    }
                    .padding(10)
                    .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct OverviewTaskBoard: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let executionCards: [OverviewTaskCard]
    let waitingCards: [OverviewTaskCard]
    let shippingCards: [OverviewTaskCard]
    let onOpenWorkspace: (UUID) -> Void
    let onAction: (OverviewWorkspaceAction) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            OverviewTaskLane(
                title: localized("overview.taskBoard.execute"),
                systemName: "bolt.fill",
                tint: LineyTheme.accent,
                items: executionCards,
                emptyText: localized("overview.taskBoard.executeEmpty"),
                onOpenWorkspace: onOpenWorkspace,
                onAction: onAction
            )
            OverviewTaskLane(
                title: localized("overview.taskBoard.waiting"),
                systemName: "pause.circle.fill",
                tint: LineyTheme.warning,
                items: waitingCards,
                emptyText: localized("overview.taskBoard.waitingEmpty"),
                onOpenWorkspace: onOpenWorkspace,
                onAction: onAction
            )
            OverviewTaskLane(
                title: localized("overview.taskBoard.ship"),
                systemName: "paperplane.fill",
                tint: LineyTheme.success,
                items: shippingCards,
                emptyText: localized("overview.taskBoard.shipEmpty"),
                onOpenWorkspace: onOpenWorkspace,
                onAction: onAction
            )
        }
    }
}

private struct OverviewTaskLane: View {
    let title: String
    let systemName: String
    let tint: Color
    let items: [OverviewTaskCard]
    let emptyText: String
    let onOpenWorkspace: (UUID) -> Void
    let onAction: (OverviewWorkspaceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            if items.isEmpty {
                OverviewEmptyLine(text: emptyText)
            } else {
                ForEach(items.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button(item.workspace.name) {
                                onOpenWorkspace(item.workspace.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button(item.actionLabel) {
                                onAction(item.action)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tint)
                        }

                        Text(item.subtitle)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(LineyTheme.mutedText)
                        Text(item.detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LineyTheme.secondaryText)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct OverviewPullRequestInboxPanel: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let sections: [OverviewPullRequestInboxSection]
    let readyTargets: [WorkspaceGitHubTarget]
    let behindTargets: [WorkspaceGitHubTarget]
    let releaseContextTargets: [WorkspaceGitHubTarget]
    let onOpenWorkspace: (UUID) -> Void
    let onAction: (OverviewWorkspaceAction) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("overview.inbox.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localized("overview.inbox.subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                Spacer()
                Text(localizedFormat("overview.inbox.openCountFormat", sections.reduce(0) { $0 + $1.items.count }))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            HStack(spacing: 10) {
                if !readyTargets.isEmpty {
                    Button(localizedFormat("overview.inbox.queueReadyFormat", readyTargets.count)) {
                        onAction(.queuePullRequests(readyTargets))
                    }
                }
                if !behindTargets.isEmpty {
                    Button(localizedFormat("overview.inbox.updateBehindFormat", behindTargets.count)) {
                        onAction(.updatePullRequestBranches(behindTargets))
                    }
                }
                if !releaseContextTargets.isEmpty {
                    Button(localized("overview.inbox.copyReleaseContext")) {
                        onAction(.copyPullRequestReleaseNotesBatch(releaseContextTargets))
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(section.category.title, systemImage: section.category.systemName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(section.category.tint)
                        Spacer()
                        Text("\(section.items.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(section.category.tint)
                    }

                    ForEach(section.items.prefix(6)) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.pullRequest.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.statusBadge)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(section.category.tint)
                                }

                                Button(item.workspace.name) {
                                    onOpenWorkspace(item.workspace.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(LineyTheme.accent)

                                Text(item.subtitle)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(LineyTheme.mutedText)
                                Text(item.detail)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(LineyTheme.secondaryText)
                                    .lineLimit(2)
                                if let reviewLine = item.reviewLine {
                                    Text(reviewLine)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(LineyTheme.mutedText)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: 0)

                            Button(item.actionLabel) {
                                onAction(item.action)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(section.category.tint)
                        }
                        .padding(10)
                        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(12)
                .background(section.category.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(section.category.tint.opacity(0.14), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct OverviewBlockerPanel: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let groups: [OverviewBlockerGroup]
    let onOpenWorkspace: (UUID) -> Void
    let onAction: (OverviewWorkspaceAction) -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("overview.blockers.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localized("overview.blockers.subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                Spacer()
                Text(localizedFormat("overview.blockers.countFormat", groups.reduce(0) { $0 + $1.count }))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(group.tint)
                        Spacer()
                        Text("\(group.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(group.tint)
                    }

                    ForEach(group.items.prefix(4)) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Button(item.workspace.name) {
                                    onOpenWorkspace(item.workspace.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))

                                Text(item.subtitle)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(LineyTheme.mutedText)
                                Text(item.detail)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(LineyTheme.secondaryText)
                            }

                            Spacer()

                            Button(item.actionLabel) {
                                onAction(item.action)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(group.tint)
                        }
                        .padding(10)
                        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(12)
                .background(group.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(group.tint.opacity(0.14), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct OverviewTimelineRow: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let item: OverviewTimelineItem
    let onOpenWorkspace: () -> Void
    let onReplay: (() -> Void)?

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var timestampLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: Date(timeIntervalSince1970: item.entry.timestamp), relativeTo: Date())
    }

    private var accent: Color {
        switch item.entry.kind {
        case .workflow:
            return LineyTheme.accent
        case .command:
            return LineyTheme.warning
        case .agent:
            return LineyTheme.localAccent
        case .remote:
            return LineyTheme.secondaryText
        case .github:
            return LineyTheme.success
        case .release:
            return LineyTheme.danger
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.entry.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(item.entry.kind.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Spacer()
                    Text(timestampLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }

                Text(item.entry.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LineyTheme.secondaryText)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button(action: onOpenWorkspace) {
                        Text(item.workspace.name)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LineyTheme.accent)

                    if let worktreeName = item.worktreeName {
                        Text(worktreeName)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(LineyTheme.mutedText)
                    }

                    Spacer()

                    if let onReplay {
                        Button(localized("overview.timeline.replay"), action: onReplay)
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(10)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct OverviewEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(LineyTheme.mutedText)
    }
}

private extension OverviewPullRequestInboxCategory {
    var tint: Color {
        switch self {
        case .failing:
            return LineyTheme.danger
        case .behind:
            return LineyTheme.warning
        case .review:
            return LineyTheme.accent
        case .ready:
            return LineyTheme.success
        }
    }
}

private extension OverviewBlockerGroup {
    var tint: Color {
        style.tint
    }
}

private extension OverviewBlockerGroupStyle {
    var tint: Color {
        switch self {
        case .failingChecks:
            return LineyTheme.danger
        case .mergeReadiness(let readiness):
            switch readiness {
            case .behind, .draft:
                return LineyTheme.warning
            case .changesRequested, .conflicted, .blocked:
                return LineyTheme.danger
            case .ready:
                return LineyTheme.success
            case .checking, .closed:
                return LineyTheme.secondaryText
            }
        }
    }
}
