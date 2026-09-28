import SwiftUI
import Combine

struct OverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    let onDismiss: () -> Void
    @State private var query = ""
    @State private var items: [WorkbenchItem] = []
    @State private var showActivity = false

    private func text(_ key: String) -> String { localization.string(key) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("main.overview.title")).font(.title2.bold())
                    Text(text("workbench.overviewSubtitle")).foregroundStyle(LineyTheme.secondaryText)
                }
                Spacer()
                Button(text("workbench.newTerminal")) { store.createStandaloneTerminal() }
                Button(action: onDismiss) { Image(systemName: "xmark") }.help(text("workbench.dismiss"))
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    attentionSection
                    continueSection
                    directorySection
                    DisclosureGroup(text("overview.timeline.title"), isExpanded: $showActivity) {
                        ForEach(OverviewViewModel(workspaces: store.workspaces).recentActivities) { item in
                            HStack {
                                Text(item.workspace.name).fontWeight(.medium)
                                Text(item.entry.title).lineLimit(1)
                                Spacer()
                                Text(Date(timeIntervalSince1970: item.entry.timestamp), style: .relative).foregroundStyle(LineyTheme.mutedText)
                            }.padding(.vertical, 4)
                        }
                    }
                }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }
        }
        .background(LineyTheme.appBackground)
        .task {
            while !Task.isCancelled {
                items = store.workbenchItems()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onReceive(store.objectWillChange) { _ in
            DispatchQueue.main.async { items = store.workbenchItems() }
        }
    }

    private var attentionSection: some View {
        let groups = WorkbenchAttention.make(items: items)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("workbench.attention", count: groups.count)
            if groups.isEmpty {
                Label(text("workbench.allClear"), systemImage: "checkmark.circle")
                    .foregroundStyle(LineyTheme.secondaryText).padding(.vertical, 12)
            }
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: group.priority < 2 ? "exclamationmark.bubble" : "arrow.triangle.branch")
                        .foregroundStyle(group.priority < 3 ? LineyTheme.warning : LineyTheme.success)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(group.item.workspace.name + " / " + group.item.context).fontWeight(.semibold)
                            if group.isUnread { Circle().fill(LineyTheme.accent).frame(width: 6, height: 6) }
                        }
                        Text(group.headline).font(.callout)
                        Text(group.details).font(.caption).foregroundStyle(LineyTheme.secondaryText)
                        if let updatedAt = group.updatedAt {
                            Text(updatedAt, style: .relative).font(.caption).foregroundStyle(LineyTheme.mutedText)
                        }
                    }
                    Spacer()
                    Button(text(group.actionLabel)) {
                        switch group.action {
                        case .terminal: store.openWorkbenchLocation(group.item.location)
                        case .checks: store.dispatch(.openFailingCheckDetails(group.item.id.workspaceID, group.item.id.worktreePath))
                        case .pullRequest: store.dispatch(.openPullRequest(group.item.id.workspaceID, group.item.id.worktreePath))
                        case .refresh: store.refresh(group.item.workspace)
                        }
                    }
                    Menu {
                        ForEach(items.filter {
                            $0.id.workspaceID == group.item.id.workspaceID &&
                            $0.id.worktreePath == group.item.id.worktreePath && $0.needsAttention
                        }) { item in
                            Button(item.tab.title + " · " + text(item.statusKey)) {
                                store.openWorkbenchLocation(item.location)
                            }
                        }
                        let status = group.item.workspace.gitHubStatuses[group.item.id.worktreePath]
                        if status?.checksSummary?.failingCount ?? 0 > 0 {
                            Button(text("workbench.checks")) {
                                store.dispatch(.openFailingCheckDetails(group.item.id.workspaceID, group.item.id.worktreePath))
                            }
                        }
                        if status?.pullRequest != nil {
                            Button(text("workbench.pullRequest")) {
                                store.dispatch(.openPullRequest(group.item.id.workspaceID, group.item.id.worktreePath))
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                }.padding(14)
                    .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var continueSection: some View {
        let recent = items.filter { $0.isPinned || $0.lastVisitedAt != nil || $0.isStarted }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            let lhs = $0.lastVisitedAt ?? .distantPast
            let rhs = $1.lastVisitedAt ?? .distantPast
            return lhs == rhs ? $0.id.id < $1.id.id : lhs > rhs
        }
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("workbench.continue", count: recent.count)
            if recent.isEmpty { Text(text("workbench.continueEmpty")).foregroundStyle(LineyTheme.secondaryText) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 500))], spacing: 12) {
                ForEach(Array(recent.prefix(12))) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.workspace.name).fontWeight(.semibold).lineLimit(1)
                            Spacer()
                            pinButton(item)
                        }
                        Text(item.context + " · " + item.tab.title).font(.callout).lineLimit(1)
                        HStack {
                            Text(text(item.statusKey))
                            if item.changedFileCount > 0 { Text("· \(item.changedFileCount) " + text("workbench.changed")) }
                        }.font(.caption).foregroundStyle(LineyTheme.secondaryText)
                        HStack {
                            Button(text("workbench.resume")) { store.openWorkbenchLocation(item.location) }
                            if item.changedFileCount > 0 { Button(text("workbench.diff")) { openDiff(item) } }
                            Spacer()
                            itemMenu(item)
                        }
                    }.padding(16)
                        .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("workbench.directory", count: store.workspaces.count)
            TextField(text("canvas.search.placeholder"), text: $query).textFieldStyle(.roundedBorder)
            ForEach(items.filter {
                query.isEmpty || [$0.workspace.name, $0.context, $0.tab.title, $0.directory]
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }) { item in
                HStack {
                    Image(systemName: item.workspace.isStandaloneTerminal ? "terminal" : "folder")
                    Button { store.openWorkbenchLocation(item.location) } label: {
                        Text(item.workspace.name + " / " + item.context + " / " + item.tab.title).lineLimit(1)
                    }.buttonStyle(.plain)
                    Spacer()
                    pinButton(item)
                    itemMenu(item)
                }.padding(.vertical, 6)
            }
        }
    }

    private func sectionTitle(_ key: String, count: Int) -> some View {
        HStack {
            Text(text(key)).font(.headline)
            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(LineyTheme.mutedText)
        }
    }

    private func pinButton(_ item: WorkbenchItem) -> some View {
        Button {
            store.toggleWorkbenchPin(item.id)
            items = store.workbenchItems()
        } label: { Image(systemName: item.isPinned ? "pin.fill" : "pin") }
            .buttonStyle(.plain).help(text(item.isPinned ? "canvas.card.unpin" : "canvas.card.pin"))
    }

    private func itemMenu(_ item: WorkbenchItem) -> some View {
        Menu {
            Button(text("main.canvas.show")) { store.openWorkbenchLocation(item.location, inCanvas: true) }
            ForEach(item.workspace.settings.workflows) { workflow in
                Button(workflow.name) { store.dispatch(.runWorkflow(item.workspace.id, workflow.id)) }
            }
            if !item.workspace.isRemote {
                Button(text("workbench.atDirectory")) { store.createStandaloneTerminal(at: item.directory) }
            }
        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
    }

    private func openDiff(_ item: WorkbenchItem) {
        DiffWindowManager.shared.show(worktreePath: item.id.worktreePath, branchName: item.context,
                                     emptyStateMessage: text("main.diff.workingDirectoryClean"))
    }
}
