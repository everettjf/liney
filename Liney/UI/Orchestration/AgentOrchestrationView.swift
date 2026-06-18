//
//  AgentOrchestrationView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

/// The cross-worktree orchestration panel: every running agent across every
/// open workspace, attention-first, one click from the pane that needs you.
struct AgentOrchestrationView: View {
    @ObservedObject var store: AgentOrchestrationStore
    var onReveal: (AgentOrchestrationRow) -> Void
    var onReviewDiff: (AgentOrchestrationRow) -> Void
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.hasAnyAgents {
                content
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agents").font(.headline)
                Text(store.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(store.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.workspaceName.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                        ForEach(group.rows) { row in
                            AgentRowView(
                                row: row,
                                onReveal: { onReveal(row) },
                                onReviewDiff: { onReviewDiff(row) }
                            )
                        }
                    }
                }
                if !store.notifications.isEmpty {
                    notificationsSection
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT NOTIFICATIONS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 6)
            ForEach(store.notifications) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(AgentRowView.color(for: item.status))
                        .frame(width: 6, height: 6)
                    Text(item.title).font(.caption).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No agents running")
                .foregroundStyle(.secondary)
            Text("Agents started in any workspace show up here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentRowView: View {
    let row: AgentOrchestrationRow
    var onReveal: () -> Void
    var onReviewDiff: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Self.color(for: row.status))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.displayName).font(.body.weight(.medium))
                        Text(row.status.rawValue)
                            .font(.caption2)
                            .foregroundStyle(Self.color(for: row.status))
                        if !row.reported {
                            Text("detected")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if row.focused {
                            Image(systemName: "scope").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    HStack(spacing: 8) {
                        if let branch = row.branch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .labelStyle(.titleAndIcon)
                        }
                        if let pr = row.prNumber {
                            Text("PR #\(pr)\(row.prState.map { " · \($0.lowercased())" } ?? "")")
                        }
                        if !row.listeningPorts.isEmpty {
                            Text(row.listeningPorts.map { ":\($0)" }.joined(separator: " "))
                        }
                        if row.changedFileCount > 0 {
                            Label("\(row.changedFileCount)", systemImage: "plus.forwardslash.minus")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    Text(row.cwd)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if row.canReviewDiff {
                    Button(action: onReviewDiff) {
                        Label("Review", systemImage: "eye")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Review the \(row.changedFileCount) changed file(s) in this worktree")
                }
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    static func color(for status: AgentReportedState) -> Color {
        switch status {
        case .waiting: return .orange
        case .error: return .red
        case .running: return .green
        case .done: return .secondary
        }
    }

    static func color(for status: IslandItemStatus) -> Color {
        switch status {
        case .waitingForInput: return .orange
        case .error: return .red
        case .running: return .green
        case .done: return .secondary
        }
    }
}
