//
//  IslandExpandedView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct IslandExpandedView: View {
    @ObservedObject var state: IslandNotificationState
    let controller: IslandPanelController

    var body: some View {
        VStack(spacing: 0) {
            islandTabBar

            Divider()
                .background(.white.opacity(0.1))

            Group {
                switch state.selectedTab {
                case .workspaces:
                    workspacesTabContent
                case .notifications:
                    notificationsTabContent
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var islandTabBar: some View {
        HStack(spacing: 2) {
            ForEach(IslandTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        state.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.system(size: 11))
                        Text(tabTitle(for: tab))
                            .font(.system(size: 12, weight: .medium))
                        if tab == .notifications && state.badgeCount > 0 {
                            Text("\(state.badgeCount)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(.blue))
                        }
                    }
                    .foregroundStyle(state.selectedTab == tab ? .white : .white.opacity(0.45))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(state.selectedTab == tab ? .white.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func tabIcon(for tab: IslandTab) -> String {
        switch tab {
        case .workspaces: return "square.grid.2x2"
        case .notifications: return "bell"
        }
    }

    private func tabTitle(for tab: IslandTab) -> String {
        switch tab {
        case .workspaces: return "Workspaces"
        case .notifications: return "Notifications"
        }
    }

    // MARK: - Workspaces Tab

    @ViewBuilder
    private var workspacesTabContent: some View {
        if let store = controller.workspaceStore {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.workspaces) { workspace in
                        IslandWorkspaceRow(
                            workspace: workspace,
                            isSelected: workspace.id == store.selectedWorkspaceID,
                            controller: controller
                        )
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
        } else {
            Text("No workspaces")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Notifications Tab

    @ViewBuilder
    private var notificationsTabContent: some View {
        if state.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.2))
                Text("No notifications")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.items) { item in
                        if let prompt = item.prompt {
                            IslandPromptRow(item: item, prompt: prompt, controller: controller)
                        } else {
                            IslandNotificationRow(item: item, controller: controller)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Workspace Row

private struct IslandWorkspaceRow: View {
    @ObservedObject var workspace: WorkspaceModel
    let isSelected: Bool
    let controller: IslandPanelController

    var body: some View {
        Button {
            controller.navigateToWorkspace(workspace)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: workspaceIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !workspace.currentBranch.isEmpty {
                            Label(workspace.currentBranch, systemImage: "arrow.triangle.branch")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        if workspace.sessionController.activeSessionCount > 0 {
                            Label("\(workspace.sessionController.activeSessionCount)", systemImage: "terminal")
                                .font(.system(size: 10))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }

                Spacer(minLength: 4)

                if workspace.hasUncommittedChanges {
                    Text("\(workspace.changedFileCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.orange.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? .white.opacity(0.1) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var workspaceIcon: String {
        if let override = workspace.workspaceIconOverride {
            return override.symbolName
        }
        return workspace.kind == .repository ? "arrow.triangle.branch" : "terminal"
    }

    private var iconColor: Color {
        if let override = workspace.workspaceIconOverride {
            return override.palette.descriptor.foreground
        }
        return workspace.kind == .repository ? .blue : .green
    }
}

// MARK: - Notification Row

private struct IslandNotificationRow: View {
    let item: IslandNotificationItem
    let controller: IslandPanelController

    var body: some View {
        Button {
            controller.navigateToItem(item)
        } label: {
            HStack(spacing: 10) {
                islandStatusIcon(for: item)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if item.status == .done {
                        Text("Done — click to jump")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else if let body = item.body {
                        Text(body)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    if let agentName = item.agentName {
                        IslandTagPill(text: agentName)
                    }
                    if let terminalTag = item.terminalTag {
                        IslandTagPill(text: terminalTag)
                    }
                    Text(islandElapsedText(from: item.startedAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.status == .done ? .green.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompt Row

private struct IslandPromptRow: View {
    let item: IslandNotificationItem
    let prompt: IslandPrompt
    let controller: IslandPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.cyan)
                Text("Claude asks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.cyan)
                Spacer()
            }

            Text(prompt.question)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            ForEach(prompt.options) { option in
                Button {
                    controller.navigateToItem(item)
                } label: {
                    HStack(spacing: 8) {
                        Text("\u{2318}\(option.id)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.1))
                            )

                        Text(option.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.06))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared Components

struct IslandTagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.1))
            )
    }
}

func islandElapsedText(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "\(Int(interval))s"
    } else if interval < 3600 {
        return "\(Int(interval / 60))m"
    } else {
        return "\(Int(interval / 3600))h"
    }
}
