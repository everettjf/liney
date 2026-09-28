import SwiftUI
import Combine

struct GlobalCanvasView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    let onDismiss: () -> Void
    @AppStorage("canvas.workbench.freeform") private var freeform = false
    @State private var pinnedOnly = false
    @State private var query = ""
    @State private var items: [WorkbenchItem] = []
    @State private var order: [GlobalCanvasCardID] = []
    @State private var expandedID: GlobalCanvasCardID?
    @State private var scrollID: GlobalCanvasCardID?

    private func text(_ key: String) -> String { localization.string(key) }

    private var visibleItems: [WorkbenchItem] {
        let matches = items.filter { item in
            item.isStarted && (!pinnedOnly || item.isPinned) &&
            (query.isEmpty || [item.workspace.name, item.context, item.tab.title, item.directory]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return matches.sorted { positions[$0.id, default: .max] < positions[$1.id, default: .max] }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(text("main.canvas.title")).font(.title2.bold())
                Picker(text("workbench.layout"), selection: $freeform) {
                    Text(text("workbench.grid")).tag(false)
                    Text(text("workbench.freeform")).tag(true)
                }.pickerStyle(.segmented).frame(width: 200)
                Picker(text("workbench.scope"), selection: $pinnedOnly) {
                        Text(text("workbench.allStarted")).tag(false)
                        Text(text("workbench.pinned")).tag(true)
                }.pickerStyle(.segmented).frame(width: 200)
                if !freeform {
                    TextField(text("canvas.search.placeholder"), text: $query).textFieldStyle(.roundedBorder)
                }
                Spacer(minLength: 0)
                Button {
                    pinnedOnly = false
                    query = ""
                    expandedID = nil
                    store.createStandaloneTerminal(keepCanvas: true)
                    refresh()
                    scrollID = items.first { $0.workspace.id == store.selectedWorkspaceID }?.id
                } label: { Image(systemName: "plus") }
                    .help(text("workbench.newTerminal"))
                    .accessibilityLabel(text("workbench.newTerminal"))
                Button(action: onDismiss) { Image(systemName: "xmark") }.help(text("canvas.exit"))
            }.padding(16)
            Divider()
            if let expandedID, let item = items.first(where: { $0.id == expandedID }) {
                card(item, expanded: true).padding(16)
            } else if freeform {
                FreeformCanvasView(onDismiss: onDismiss, pinnedOnly: pinnedOnly, workbenchItems: items,
                    onExpand: { id in expandedID = id })
            } else {
                GeometryReader { geometry in
                    let count = max(1, min(3, Int(geometry.size.width / 520)))
                    ScrollView {
                        if visibleItems.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "terminal").font(.largeTitle)
                                Text(text(pinnedOnly ? "workbench.noPins" : "canvas.empty.noLiveTerminalViews"))
                                Button(text("workbench.newTerminal")) {
                                    pinnedOnly = false
                                    query = ""
                                    store.createStandaloneTerminal(keepCanvas: true)
                                }
                            }.padding(50).frame(maxWidth: .infinity)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: count), spacing: 16) {
                            ForEach(visibleItems) { item in
                                card(item, expanded: false).frame(height: 380).id(item.id)
                            }
                        }.scrollTargetLayout().padding(16)
                    }.scrollPosition(id: $scrollID, anchor: .top)
                }
            }
        }
        .background(LineyTheme.appBackground)
        .task {
            while !Task.isCancelled {
                refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onReceive(store.objectWillChange) { _ in DispatchQueue.main.async { refresh() } }
        .onChange(of: freeform) { _, _ in expandedID = nil }
    }

    private func refresh() {
        let next = store.workbenchItems()
        let ids = Set(next.map(\.id))
        order.removeAll { !ids.contains($0) }
        let known = Set(order)
        order.append(contentsOf: next.map(\.id).filter { !known.contains($0) })
        items = next
        if let expandedID, !ids.contains(expandedID) { self.expandedID = nil }
    }

    private func card(_ item: WorkbenchItem, expanded: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.workspace.name + " / " + item.tab.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(item.context).font(.caption).foregroundStyle(LineyTheme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { store.toggleWorkbenchPin(item.id); refresh() } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                }.help(text(item.isPinned ? "canvas.card.unpin" : "canvas.card.pin"))
                Button {
                    if expanded {
                        expandedID = nil
                        scrollID = item.id
                    } else {
                        store.openWorkbenchLocation(item.location, inCanvas: true)
                        expandedID = item.id
                    }
                } label: { Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    .help(text(expanded ? "workbench.backToGrid" : "workbench.expand"))
                Button { store.openWorkbenchLocation(item.location) } label: { Image(systemName: "arrow.up.right.square") }
                    .help(text("canvas.card.openTab"))
            }.buttonStyle(.plain).padding(12)
            HStack {
                Text(text(item.statusKey))
                if item.isUnread { Circle().fill(LineyTheme.accent).frame(width: 5, height: 5) }
                if item.changedFileCount > 0 { Text("· \(item.changedFileCount) " + text("workbench.changed")) }
                Spacer()
                if let status = item.workspace.gitHubStatuses[item.id.worktreePath] {
                    if status.refreshError != nil { Text(text("workbench.stale")) }
                    else if let checks = status.checksSummary, checks.failingCount > 0 {
                        Text("\(checks.failingCount) " + text("workbench.failingChecks"))
                    }
                }
            }.font(.caption).foregroundStyle(item.needsAttention ? LineyTheme.warning : LineyTheme.secondaryText)
                .padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            if let controller = item.controller, let layout = item.tab.layout {
                WorkspaceCanvasLiveNodeView(sessionController: controller, node: layout, allowsInteraction: true,
                    onActivate: { paneID in
                        store.openWorkbenchLocation(WorkbenchLocation(cardID: item.id, paneID: paneID), inCanvas: true)
                    },
                    restoreFocusPaneID: store.selectedWorkspaceID == item.id.workspaceID && item.workspace.activeTabID == item.id.tabID
                        ? controller.focusedPaneID : nil)
            } else {
                Text(text("canvas.card.noLiveTerminal")).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LineyTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(item.needsAttention ? LineyTheme.warning : LineyTheme.border))
    }
}
