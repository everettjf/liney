//
//  DeskView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct DeskView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject private var localization = LocalizationManager.shared
    let onTap: () -> Void

    @State private var isHovering = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var sessions: [ShellSession] {
        let controller = workspace.sessionController
        return workspace.paneOrder.compactMap { controller.session(for: $0) }
    }

    private var accentColor: Color {
        workspace.supportsRepositoryFeatures ? LineyTheme.accent : LineyTheme.localAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deskHeader
            deskSurface
            deskFooter
        }
        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovering ? accentColor.opacity(0.5) : LineyTheme.border, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
        .shadow(color: .black.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 12 : 6, y: 4)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private var deskHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: workspace.supportsRepositoryFeatures ? "arrow.triangle.branch" : "terminal.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 18, height: 18)
                .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(workspace.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer()

            if workspace.supportsRepositoryFeatures {
                HStack(spacing: 3) {
                    Circle()
                        .fill(workspace.hasUncommittedChanges ? LineyTheme.warning : LineyTheme.success)
                        .frame(width: 6, height: 6)
                    Text(workspace.currentBranch)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LineyTheme.border).frame(height: 1)
        }
    }

    private var deskSurface: some View {
        let sessionList = sessions
        return VStack(spacing: 0) {
            if sessionList.isEmpty {
                emptyDesk
            } else {
                monitorsGrid(sessions: sessionList)
            }
        }
        .frame(minHeight: 80)
        .padding(10)
    }

    private var emptyDesk: some View {
        VStack(spacing: 6) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 20))
                .foregroundStyle(LineyTheme.mutedText.opacity(0.4))
            Text(localized("desk.empty.noActiveSessions"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LineyTheme.mutedText.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private func monitorsGrid(sessions: [ShellSession]) -> some View {
        let columns = sessions.count <= 2
            ? [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            : [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(sessions) { session in
                MonitorView(session: session, accentColor: accentColor)
            }
        }
    }

    private var deskFooter: some View {
        HStack(spacing: 8) {
            let worktreeCount = workspace.worktrees.count
            if worktreeCount > 1 {
                Label(localizedFormat("desk.footer.worktreesFormat", worktreeCount), systemImage: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            Spacer()

            Text(localizedFormat("desk.footer.sessionsFormat", sessions.count, sessions.count == 1 ? "" : localized("desk.footer.sessionsPluralSuffix")))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(LineyTheme.mutedText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(LineyTheme.border).frame(height: 1)
        }
    }
}

private struct MonitorView: View {
    @ObservedObject var session: ShellSession
    @ObservedObject private var localization = LocalizationManager.shared
    let accentColor: Color

    @State private var glowPhase: Bool = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var isActive: Bool { session.hasActiveProcess }

    var body: some View {
        VStack(spacing: 4) {
            // Monitor screen
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? LineyTheme.paneBackground : Color.black.opacity(0.3))

                if isActive {
                    // Scanline effect
                    VStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(accentColor.opacity(Double.random(in: 0.15...0.4)))
                                .frame(height: 2)
                                .padding(.horizontal, 3)
                                .offset(x: CGFloat.random(in: -2...2))
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Power LED
                Circle()
                    .fill(isActive ? LineyTheme.success : LineyTheme.danger.opacity(0.4))
                    .frame(width: 3, height: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
            .frame(height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isActive ? accentColor.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 0.5)
            )

            // Monitor stand
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.08))
                .frame(width: 8, height: 3)

            // Label
            Text(session.title.isEmpty ? localized("desk.monitor.defaultShell") : session.title)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(LineyTheme.mutedText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
