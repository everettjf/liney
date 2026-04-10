//
//  GlobalCanvasView.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Combine
import SwiftUI

struct GlobalCanvasView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedWorkspaceFilters: Set<UUID> = []
    @State private var cardLayouts: [GlobalCanvasCardID: GlobalCanvasCardLayout] = [:]
    @State private var canvasOffset: CGSize = .zero
    @State private var lastCanvasOffset: CGSize = .zero
    @State private var canvasScale: CGFloat = 1
    @State private var lastCanvasScale: CGFloat = 1
    @State private var viewportSize: CGSize = .zero
    @State private var hasPerformedInitialFit = false
    @State private var dragOrigins: [GlobalCanvasCardID: CGPoint] = [:]
    @State private var cachedCards: [GlobalCanvasCardSnapshot] = []

    private let defaultCardSize = CGSize(width: 560, height: 360)
    private let minimizedCardHeight: CGFloat = 96
    private let minCanvasScale: CGFloat = 0.45
    private let maxCanvasScale: CGFloat = 1.8
    private let zoomStep: CGFloat = 1.14
    private let gridSpacing: CGFloat = 18
    private let gridTopInset: CGFloat = 128
    private let gridSideInset: CGFloat = 32

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var allCards: [GlobalCanvasCardSnapshot] {
        cachedCards
    }

    private var workspaceFilters: [GlobalCanvasWorkspaceFilter] {
        Dictionary(grouping: allCards, by: \.workspaceID)
            .compactMap { workspaceID, cards in
                guard let first = cards.first else { return nil }
                return GlobalCanvasWorkspaceFilter(
                    workspaceID: workspaceID,
                    workspaceName: first.workspaceName,
                    liveCardCount: cards.count,
                    pinnedCardCount: cards.filter { layout(for: $0).isPinned }.count
                )
            }
            .sorted { lhs, rhs in
                lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
            }
    }

    private var visibleCards: [GlobalCanvasCardSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceFiltered = selectedWorkspaceFilters.isEmpty
            ? allCards
            : allCards.filter { selectedWorkspaceFilters.contains($0.workspaceID) }

        guard !normalizedQuery.isEmpty else {
            return workspaceFiltered
        }

        return workspaceFiltered.filter { card in
            let haystacks = [
                card.workspaceName,
                card.worktreeTitle,
                card.worktreePath,
                card.tab.title,
                card.primaryPath
            ]
            return haystacks.contains {
                $0.localizedCaseInsensitiveContains(normalizedQuery)
            }
        }
    }

    private var activeCardID: GlobalCanvasCardID? {
        guard let workspace = store.selectedWorkspace,
              let tabID = workspace.activeTabID else {
            return nil
        }
        return GlobalCanvasCardID(
            workspaceID: workspace.id,
            worktreePath: workspace.activeWorktreePath,
            tabID: tabID
        )
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedWorkspaceFilters.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                GlobalCanvasBackdrop()

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(canvasPanGesture)

                GlobalCanvasScrollWheelMonitor { event in
                    handleScrollWheel(event)
                }
                .frame(width: 0, height: 0)

                if allCards.isEmpty {
                    emptyState(
                        title: localized("canvas.empty.noLiveTerminalViews"),
                        message: localized("canvas.empty.noLiveTerminalViewsMessage")
                    )
                } else if visibleCards.isEmpty {
                    emptyState(
                        title: localized("canvas.empty.noMatchingCards"),
                        message: localized("canvas.empty.noMatchingCardsMessage")
                    )
                } else {
                    ZStack {
                        ForEach(Array(visibleCards.enumerated()), id: \.element.id) { index, card in
                            let layout = cardLayouts[card.id] ?? fallbackLayout(for: index)
                            let screenCenter = screenPosition(for: layout.position)

                            GlobalCanvasCardView(
                                card: card,
                                layout: layout,
                                canvasScale: canvasScale,
                                accentTint: tint(for: layout.colorGroup),
                                onSelect: {
                                    store.selectGlobalCanvasCard(card.id)
                                },
                                onOpen: {
                                    store.selectGlobalCanvasCard(card.id)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        onDismiss()
                                    }
                                },
                                onTogglePin: {
                                    togglePinned(for: card.id)
                                },
                                onToggleMinimize: {
                                    toggleMinimized(for: card.id)
                                },
                                onSelectColorGroup: { colorGroup in
                                    setColorGroup(colorGroup, for: card.id)
                                },
                                onDragCommit: { translation in
                                    commitDrag(for: card.id, translation: translation)
                                }
                            )
                            .frame(width: layout.size.width, height: layout.size.height)
                            .scaleEffect(canvasScale, anchor: .center)
                            .position(x: screenCenter.x, y: screenCenter.y)
                            .zIndex(zIndex(for: card, layout: layout))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                headerPanel
                    .padding(16)
                    .zIndex(2)

                exitCanvasButton
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(2)

                canvasToolbar
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .zIndex(2)
            }
            .clipped()
            .simultaneousGesture(canvasZoomGesture)
            .onAppear {
                viewportSize = proxy.size
                refreshCards()
                restoreCanvasState()
            }
            .onReceive(store.objectWillChange) { _ in
                refreshCards()
            }
            .onChange(of: proxy.size) { _, newSize in
                viewportSize = newSize
                if !hasPerformedInitialFit {
                    fitToView(canvasSize: newSize)
                    hasPerformedInitialFit = true
                    persistCanvasState()
                }
            }
            .onChange(of: allCards.map(\.id)) { _, _ in
                let hadMissingLayouts = ensureLayouts()
                if visibleCards.isEmpty == false {
                    if hadMissingLayouts {
                        organizeCardsAsGrid()
                    } else {
                        fitToView(canvasSize: viewportSize)
                    }
                }
                persistCanvasState()
            }
            .onChange(of: query) { _, _ in
                fitToView(canvasSize: viewportSize)
            }
            .onChange(of: selectedWorkspaceFilters) { _, _ in
                fitToView(canvasSize: viewportSize)
            }
            .onDisappear(perform: persistCanvasState)
        }
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("main.canvas.title"))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            HStack(spacing: 8) {
                WorkspaceCanvasBadge(
                    text: isFiltering
                        ? localizedFormat("canvas.header.visibleLiveFormat", visibleCards.count, allCards.count)
                        : localizedFormat("canvas.header.liveTabsFormat", allCards.count, allCards.count == 1 ? "" : "s"),
                    tint: LineyTheme.secondaryText
                )
                WorkspaceCanvasBadge(
                    text: localizedFormat(
                        "canvas.header.activeSessionsFormat",
                        allCards.reduce(0) { $0 + $1.activeSessionCount },
                        allCards.reduce(0) { $0 + $1.activeSessionCount } == 1 ? "" : "s"
                    ),
                    tint: LineyTheme.success
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LineyTheme.mutedText)

                TextField(
                    text: $query,
                    prompt: Text(localized("canvas.search.placeholder"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                ) {
                    EmptyView()
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LineyTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LineyTheme.sidebarSearchBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    GlobalCanvasFilterChip(
                        title: localized("canvas.filter.all"),
                        subtitle: "\(allCards.count)",
                        isSelected: selectedWorkspaceFilters.isEmpty
                    ) {
                        selectedWorkspaceFilters.removeAll()
                    }

                    ForEach(workspaceFilters) { workspace in
                        GlobalCanvasFilterChip(
                            title: workspace.workspaceName,
                            subtitle: workspace.pinnedCardCount > 0 ? "\(workspace.liveCardCount) · \(workspace.pinnedCardCount) \(localized("canvas.filter.pinSuffix"))" : "\(workspace.liveCardCount)",
                            isSelected: selectedWorkspaceFilters.contains(workspace.workspaceID)
                        ) {
                            toggleWorkspaceFilter(workspace.workspaceID)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LineyTheme.chromeBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .controlSize(.small)
    }

    private var exitCanvasButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                onDismiss()
            }
        } label: {
            Label(localized("canvas.exit"), systemImage: "xmark.circle.fill")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LineyTheme.mutedText)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LineyTheme.mutedText)
            HStack(spacing: 10) {
                if isFiltering {
                    Button(localized("canvas.clearFilters")) {
                        query = ""
                        selectedWorkspaceFilters.removeAll()
                    }
                    .buttonStyle(.bordered)
                }

                Button(localized("canvas.exit")) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canvasToolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button(localized("canvas.organize.byWorkspace")) {
                    organizeCardsByWorkspace()
                }
                Button(localized("canvas.organize.asGrid")) {
                    organizeCardsAsGrid()
                }
            } label: {
                Label(localized("canvas.organize.label"), systemImage: "square.grid.3x3")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)

            Button {
                fitToView(canvasSize: viewportSize)
            } label: {
                Label(localized("canvas.fit"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)

            Button {
                zoomOut()
            } label: {
                Label(localized("canvas.zoomOut"), systemImage: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)

            Button {
                resetZoom()
            } label: {
                Text("\(Int(canvasScale * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 36)
            }
            .buttonStyle(.bordered)

            Button {
                zoomIn()
            } label: {
                Label(localized("canvas.zoomIn"), systemImage: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
        }
        .labelStyle(.iconOnly)
        .padding(12)
        .background(LineyTheme.chromeBackground.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(LineyTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    private var canvasPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                canvasOffset = CGSize(
                    width: lastCanvasOffset.width + value.translation.width,
                    height: lastCanvasOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastCanvasOffset = canvasOffset
                persistCanvasState()
            }
    }

    private var canvasZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = min(max(lastCanvasScale * value.magnification, minCanvasScale), maxCanvasScale)
                let anchor = value.startLocation
                canvasOffset = offsetForZoom(
                    from: lastCanvasScale,
                    offset: lastCanvasOffset,
                    to: newScale,
                    anchor: anchor
                )
                canvasScale = newScale
            }
            .onEnded { _ in
                lastCanvasScale = canvasScale
                lastCanvasOffset = canvasOffset
                persistCanvasState()
            }
    }

    private func restoreCanvasState() {
        let savedState = store.globalCanvasState
        cardLayouts = Dictionary(
            uniqueKeysWithValues: savedState.cardLayouts.map { ($0.cardID, GlobalCanvasCardLayout(record: $0)) }
        )
        canvasOffset = CGSize(width: savedState.offsetX, height: savedState.offsetY)
        lastCanvasOffset = canvasOffset
        canvasScale = CGFloat(savedState.scale)
        lastCanvasScale = canvasScale
        dragOrigins = [:]
        hasPerformedInitialFit = false
        let hadMissingLayouts = ensureLayouts()

        if (savedState.cardLayouts.isEmpty || hadMissingLayouts), visibleCards.isEmpty == false {
            organizeCardsAsGrid()
        }

        if canvasScale <= 0 {
            canvasScale = 1
            lastCanvasScale = 1
        }

        hasPerformedInitialFit = true
    }

    private func refreshCards() {
        cachedCards = store.workspaces.flatMap { workspace in
            workspace.canvasStates().flatMap { state in
                state.tabs.compactMap { tab in
                    guard let controller = workspace.existingTabController(for: state.worktreePath, tabID: tab.id) else {
                        return nil
                    }
                    let cardID = GlobalCanvasCardID(
                        workspaceID: workspace.id,
                        worktreePath: state.worktreePath,
                        tabID: tab.id
                    )
                    return GlobalCanvasCardSnapshot(
                        id: cardID,
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        worktreePath: state.worktreePath,
                        worktreeTitle: workspace.worktrees.first(where: { $0.path == state.worktreePath })?.displayName
                            ?? URL(fileURLWithPath: state.worktreePath).lastPathComponent,
                        tab: tab,
                        controller: controller,
                        isSelected: workspace.isActiveCanvasCard(worktreePath: state.worktreePath, tabID: tab.id),
                        paneCount: workspace.paneCount(for: tab.id, worktreePath: state.worktreePath),
                        activeSessionCount: controller.activeSessionCount(using: state.worktreePath)
                    )
                }
            }
        }
        .sorted { lhs, rhs in
            if lhs.isSelected != rhs.isSelected {
                return lhs.isSelected
            }
            if lhs.workspaceName != rhs.workspaceName {
                return lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
            }
            if lhs.worktreeTitle != rhs.worktreeTitle {
                return lhs.worktreeTitle.localizedCaseInsensitiveCompare(rhs.worktreeTitle) == .orderedAscending
            }
            return lhs.tab.title.localizedCaseInsensitiveCompare(rhs.tab.title) == .orderedAscending
        }
    }

    @discardableResult
    private func ensureLayouts() -> Bool {
        let cardIDs = allCards.map(\.id)
        let missingIDs = cardIDs.filter { cardLayouts[$0] == nil }
        guard !missingIDs.isEmpty else {
            cardLayouts = cardLayouts.filter { cardIDs.contains($0.key) }
            return false
        }

        var nextLayouts = cardLayouts.filter { cardIDs.contains($0.key) }
        let startIndex = nextLayouts.count
        for (offset, cardID) in missingIDs.enumerated() {
            nextLayouts[cardID] = fallbackLayout(for: startIndex + offset)
        }
        cardLayouts = nextLayouts
        return true
    }

    private func organizeCardsAsGrid() {
        guard !visibleCards.isEmpty else { return }
        var nextLayouts = cardLayouts
        let targetCards = visibleCards.sorted { lhs, rhs in
            let leftLayout = layout(for: lhs)
            let rightLayout = layout(for: rhs)
            if leftLayout.isPinned != rightLayout.isPinned {
                return leftLayout.isPinned
            }
            if leftLayout.colorGroup != rightLayout.colorGroup {
                return leftLayout.colorGroup.rawValue < rightLayout.colorGroup.rawValue
            }
            if lhs.workspaceName != rhs.workspaceName {
                return lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
            }
            return lhs.tab.title.localizedCaseInsensitiveCompare(rhs.tab.title) == .orderedAscending
        }

        let cardSizes = targetCards.map { targetSize(for: $0.id) }
        let maxCardWidth = max(cardSizes.map(\.width).max() ?? defaultCardSize.width, defaultCardSize.width)
        let columns = preferredGridColumnCount(for: targetCards.count)
        var rowHeights: [CGFloat] = Array(repeating: .zero, count: Int(ceil(Double(targetCards.count) / Double(columns))))

        for (index, size) in cardSizes.enumerated() {
            let row = index / columns
            rowHeights[row] = max(rowHeights[row], size.height)
        }

        var rowOrigins: [CGFloat] = []
        var currentY = gridTopInset
        for rowHeight in rowHeights {
            rowOrigins.append(currentY)
            currentY += rowHeight + gridSpacing
        }

        for (index, card) in targetCards.enumerated() {
            let row = index / columns
            let column = index % columns
            let size = targetSize(for: card.id)
            let position = CGPoint(
                x: gridSideInset + maxCardWidth / 2 + CGFloat(column) * (maxCardWidth + gridSpacing),
                y: rowOrigins[row] + size.height / 2
            )
            var layout = layout(for: card)
            layout.position = position
            layout.size = size
            nextLayouts[card.id] = layout
        }
        cardLayouts = nextLayouts
        fitToView(canvasSize: viewportSize)
        persistCanvasState()
    }

    private func organizeCardsByWorkspace() {
        guard !visibleCards.isEmpty else { return }
        var nextLayouts = cardLayouts
        var currentY = gridTopInset
        let sectionSpacing = CGFloat(84)
        let maxColumns = 2

        let grouped = Dictionary(grouping: visibleCards, by: \.workspaceID)
            .values
            .sorted { lhs, rhs in
                guard let left = lhs.first, let right = rhs.first else { return false }
                return left.workspaceName.localizedCaseInsensitiveCompare(right.workspaceName) == .orderedAscending
            }

        for cards in grouped {
            let sortedCards = cards.sorted { lhs, rhs in
                let leftLayout = layout(for: lhs)
                let rightLayout = layout(for: rhs)
                if leftLayout.isPinned != rightLayout.isPinned {
                    return leftLayout.isPinned
                }
                if leftLayout.colorGroup != rightLayout.colorGroup {
                    return leftLayout.colorGroup.rawValue < rightLayout.colorGroup.rawValue
                }
                if lhs.worktreeTitle != rhs.worktreeTitle {
                    return lhs.worktreeTitle.localizedCaseInsensitiveCompare(rhs.worktreeTitle) == .orderedAscending
                }
                return lhs.tab.title.localizedCaseInsensitiveCompare(rhs.tab.title) == .orderedAscending
            }

            var tallestRowHeight = CGFloat.zero
            var maxBottom = currentY

            for (index, card) in sortedCards.enumerated() {
                let row = index / maxColumns
                let column = index % maxColumns
                let size = targetSize(for: card.id)
                tallestRowHeight = max(tallestRowHeight, size.height)
                let position = CGPoint(
                    x: gridSideInset + size.width / 2 + CGFloat(column) * (defaultCardSize.width + gridSpacing),
                    y: currentY + size.height / 2 + CGFloat(row) * (defaultCardSize.height + gridSpacing)
                )
                maxBottom = max(maxBottom, position.y + size.height / 2)
                var layout = layout(for: card)
                layout.position = position
                layout.size = size
                nextLayouts[card.id] = layout
            }

            currentY = maxBottom + sectionSpacing + tallestRowHeight * 0.1
        }

        cardLayouts = nextLayouts
        fitToView(canvasSize: viewportSize)
        persistCanvasState()
    }

    private func fitToView(canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let layouts = visibleCards.compactMap { cardLayouts[$0.id] }
        guard !layouts.isEmpty else { return }

        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for layout in layouts {
            minX = min(minX, layout.position.x - layout.size.width / 2)
            maxX = max(maxX, layout.position.x + layout.size.width / 2)
            minY = min(minY, layout.position.y - layout.size.height / 2)
            maxY = max(maxY, layout.position.y + layout.size.height / 2)
        }

        let padding: CGFloat = 92
        let canvasWidth = maxX - minX + padding * 2
        let canvasHeight = maxY - minY + padding * 2
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let targetScale = min(max(min(canvasSize.width / canvasWidth, canvasSize.height / canvasHeight), minCanvasScale), 1.15)

        canvasScale = targetScale
        lastCanvasScale = targetScale
        canvasOffset = CGSize(
            width: canvasSize.width / 2 - centerX * targetScale,
            height: canvasSize.height / 2 - centerY * targetScale
        )
        lastCanvasOffset = canvasOffset
        persistCanvasState()
    }

    private func resetZoom() {
        setZoom(1, anchor: viewportCenter)
    }

    private func zoomIn() {
        setZoom(canvasScale * zoomStep, anchor: viewportCenter)
    }

    private func zoomOut() {
        setZoom(canvasScale / zoomStep, anchor: viewportCenter)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        guard abs(deltaY) > abs(event.scrollingDeltaX) else { return }

        let factor = exp(CGFloat(deltaY) * 0.0035)
        let anchor = CGPoint(
            x: min(max(event.locationInWindow.x, 0), viewportSize.width),
            y: min(max(viewportSize.height - event.locationInWindow.y, 0), viewportSize.height)
        )
        setZoom(canvasScale * factor, anchor: anchor)
    }

    private func setZoom(_ proposedScale: CGFloat, anchor: CGPoint) {
        let clampedScale = min(max(proposedScale, minCanvasScale), maxCanvasScale)
        guard abs(clampedScale - canvasScale) > 0.0001 else { return }

        canvasOffset = offsetForZoom(
            from: canvasScale,
            offset: canvasOffset,
            to: clampedScale,
            anchor: anchor
        )
        canvasScale = clampedScale
        lastCanvasScale = clampedScale
        lastCanvasOffset = canvasOffset
        persistCanvasState()
    }

    private func offsetForZoom(from baseScale: CGFloat, offset baseOffset: CGSize, to newScale: CGFloat, anchor: CGPoint) -> CGSize {
        guard baseScale > 0 else { return baseOffset }
        let canvasX = (anchor.x - baseOffset.width) / baseScale
        let canvasY = (anchor.y - baseOffset.height) / baseScale
        return CGSize(
            width: anchor.x - canvasX * newScale,
            height: anchor.y - canvasY * newScale
        )
    }

    private var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    private func preferredGridColumnCount(for cardCount: Int) -> Int {
        guard cardCount > 1 else { return 1 }
        let aspectRatio = max(viewportSize.width, defaultCardSize.width) / max(viewportSize.height, defaultCardSize.height)
        let horizontalBias = max(aspectRatio, 1.35)
        let idealColumns = Int(ceil(sqrt(Double(cardCount) * Double(horizontalBias))))
        return min(cardCount, max(2, idealColumns))
    }

    private func screenPosition(for canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * canvasScale + canvasOffset.width,
            y: canvasPoint.y * canvasScale + canvasOffset.height
        )
    }

    private func fallbackLayout(for index: Int) -> GlobalCanvasCardLayout {
        let columns = preferredGridColumnCount(for: max(allCards.count, 1))
        let row = index / columns
        let column = index % columns
        let position = CGPoint(
            x: gridSideInset + defaultCardSize.width / 2 + CGFloat(column) * (defaultCardSize.width + gridSpacing),
            y: gridTopInset + defaultCardSize.height / 2 + CGFloat(row) * (defaultCardSize.height + gridSpacing)
        )
        return GlobalCanvasCardLayout(position: position, size: defaultCardSize)
    }

    private func persistCanvasState() {
        let records = allCards.compactMap { card in
            cardLayouts[card.id]?.record(cardID: card.id)
        }
        let nextState = GlobalCanvasStateRecord(
            scale: canvasScale,
            offsetX: canvasOffset.width,
            offsetY: canvasOffset.height,
            cardLayouts: records
        )
        store.updateGlobalCanvasState(nextState)
    }

    private func commitDrag(for cardID: GlobalCanvasCardID, translation: CGSize) {
        if dragOrigins[cardID] == nil {
            dragOrigins[cardID] = cardLayouts[cardID]?.position ?? .zero
        }
        let origin = dragOrigins[cardID] ?? .zero
        if var layout = cardLayouts[cardID] {
            layout.position = CGPoint(
                x: origin.x + translation.width / canvasScale,
                y: origin.y + translation.height / canvasScale
            )
            cardLayouts[cardID] = layout
        }
        dragOrigins[cardID] = nil
        persistCanvasState()
    }

    private func toggleWorkspaceFilter(_ workspaceID: UUID) {
        if selectedWorkspaceFilters.contains(workspaceID) {
            selectedWorkspaceFilters.remove(workspaceID)
        } else {
            selectedWorkspaceFilters.insert(workspaceID)
        }
    }

    private func togglePinned(for cardID: GlobalCanvasCardID) {
        guard var layout = cardLayouts[cardID] else { return }
        layout.isPinned.toggle()
        cardLayouts[cardID] = layout
        persistCanvasState()
    }

    private func toggleMinimized(for cardID: GlobalCanvasCardID) {
        guard var layout = cardLayouts[cardID] else { return }
        layout.isMinimized.toggle()
        layout.size = targetSize(for: layout)
        cardLayouts[cardID] = layout
        fitToView(canvasSize: viewportSize)
        persistCanvasState()
    }

    private func setColorGroup(_ colorGroup: GlobalCanvasColorGroup, for cardID: GlobalCanvasCardID) {
        guard var layout = cardLayouts[cardID] else { return }
        layout.colorGroup = colorGroup
        cardLayouts[cardID] = layout
        persistCanvasState()
    }

    private func layout(for card: GlobalCanvasCardSnapshot) -> GlobalCanvasCardLayout {
        cardLayouts[card.id] ?? fallbackLayout(for: 0)
    }

    private func targetSize(for cardID: GlobalCanvasCardID) -> CGSize {
        targetSize(for: cardLayouts[cardID] ?? fallbackLayout(for: 0))
    }

    private func targetSize(for layout: GlobalCanvasCardLayout) -> CGSize {
        CGSize(
            width: max(layout.size.width, defaultCardSize.width),
            height: layout.isMinimized ? minimizedCardHeight : max(layout.size.height, defaultCardSize.height)
        )
    }

    private func zIndex(for card: GlobalCanvasCardSnapshot, layout: GlobalCanvasCardLayout) -> Double {
        if card.isSelected {
            return 20
        }
        if layout.isPinned {
            return 10
        }
        return 1
    }

    private func tint(for colorGroup: GlobalCanvasColorGroup) -> Color {
        switch colorGroup {
        case .none:
            return LineyTheme.accent
        case .blue:
            return LineyTheme.accent
        case .teal:
            return LineyTheme.localAccent
        case .green:
            return LineyTheme.success
        case .amber:
            return LineyTheme.warning
        case .rose:
            return LineyTheme.danger
        case .slate:
            return Color(nsColor: NSColor(calibratedRed: 0.58, green: 0.65, blue: 0.76, alpha: 1))
        }
    }
}

private struct GlobalCanvasCardSnapshot: Identifiable {
    let id: GlobalCanvasCardID
    let workspaceID: UUID
    let workspaceName: String
    let worktreePath: String
    let worktreeTitle: String
    let tab: WorkspaceTabStateRecord
    let controller: WorkspaceSessionController
    let isSelected: Bool
    let paneCount: Int
    let activeSessionCount: Int

    var primaryPath: String {
        tab.panes.first?.preferredWorkingDirectory.abbreviatedPath ?? ""
    }
}

private struct GlobalCanvasWorkspaceFilter: Identifiable {
    let workspaceID: UUID
    let workspaceName: String
    let liveCardCount: Int
    let pinnedCardCount: Int

    var id: UUID { workspaceID }
}

private struct GlobalCanvasCardLayout: Hashable {
    var position: CGPoint
    var size: CGSize
    var isMinimized: Bool
    var isPinned: Bool
    var colorGroup: GlobalCanvasColorGroup

    init(
        position: CGPoint,
        size: CGSize,
        isMinimized: Bool = false,
        isPinned: Bool = false,
        colorGroup: GlobalCanvasColorGroup = .none
    ) {
        self.position = position
        self.size = size
        self.isMinimized = isMinimized
        self.isPinned = isPinned
        self.colorGroup = colorGroup
    }

    init(record: GlobalCanvasCardLayoutRecord) {
        self.position = CGPoint(x: record.centerX, y: record.centerY)
        self.size = CGSize(width: max(record.width, 560), height: max(record.height, record.isMinimized ? 96 : 360))
        self.isMinimized = record.isMinimized
        self.isPinned = record.isPinned
        self.colorGroup = record.colorGroup
    }

    func record(cardID: GlobalCanvasCardID) -> GlobalCanvasCardLayoutRecord {
        GlobalCanvasCardLayoutRecord(
            workspaceID: cardID.workspaceID,
            worktreePath: cardID.worktreePath,
            tabID: cardID.tabID,
            centerX: position.x,
            centerY: position.y,
            width: size.width,
            height: size.height,
            isMinimized: isMinimized,
            isPinned: isPinned,
            colorGroup: colorGroup
        )
    }
}

private struct GlobalCanvasFilterChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? LineyTheme.accent : LineyTheme.mutedText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(isSelected ? LineyTheme.panelRaised : LineyTheme.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(isSelected ? LineyTheme.accent.opacity(0.32) : LineyTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : LineyTheme.secondaryText)
    }
}

private struct GlobalCanvasScrollWheelMonitor: NSViewRepresentable {
    let onScroll: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onScroll: (NSEvent) -> Void
        private var monitor: Any?

        init(onScroll: @escaping (NSEvent) -> Void) {
            self.onScroll = onScroll
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.onScroll(event)
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct GlobalCanvasCardView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let card: GlobalCanvasCardSnapshot
    let layout: GlobalCanvasCardLayout
    let canvasScale: CGFloat
    let accentTint: Color
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onToggleMinimize: () -> Void
    let onSelectColorGroup: (GlobalCanvasColorGroup) -> Void
    let onDragCommit: (CGSize) -> Void

    @GestureState private var dragTranslation: CGSize = .zero

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            if layout.isMinimized {
                minimizedSummary
            } else {
                content
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .offset(
            x: dragTranslation.width / canvasScale,
            y: dragTranslation.height / canvasScale
        )
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardBorder, lineWidth: card.isSelected ? 1.4 : 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentTint.opacity(0.94))
                .frame(width: 4)
                .padding(.vertical, 8)
        }
        .overlay {
            if !card.isSelected {
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture(perform: onSelect)
            }
        }
        .shadow(color: shadowColor, radius: card.isSelected ? 16 : 8, y: 6)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(layout.colorGroup == .none ? (card.isSelected ? LineyTheme.accent : LineyTheme.secondaryText.opacity(0.55)) : accentTint)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(card.workspaceName)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentTint.opacity(0.9))
                        .lineLimit(1)

                    if layout.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(LineyTheme.warning)
                    }

                    if layout.isMinimized {
                        Image(systemName: "rectangle.compress.vertical")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(LineyTheme.mutedText)
                    }
                }

                Text(card.tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(card.primaryPath.isEmpty ? "\(card.worktreeTitle) \(localized("canvas.card.worktreeSuffix"))" : card.primaryPath)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if layout.colorGroup != .none {
                WorkspaceCanvasBadge(text: layout.colorGroup.title, tint: accentTint)
            }

            WorkspaceCanvasBadge(
                text: localizedFormat("canvas.card.panesFormat", card.paneCount, card.paneCount == 1 ? "" : "s"),
                tint: card.isSelected ? accentTint : LineyTheme.secondaryText
            )

            Menu {
                Button(layout.isPinned ? localized("canvas.card.unpin") : localized("canvas.card.pin")) {
                    onTogglePin()
                }
                Button(layout.isMinimized ? localized("canvas.card.expand") : localized("canvas.card.minimize")) {
                    onToggleMinimize()
                }

                Divider()

                ForEach(GlobalCanvasColorGroup.allCases) { colorGroup in
                    Button(colorGroup == layout.colorGroup ? "\(colorGroup.title) ✓" : colorGroup.title) {
                        onSelectColorGroup(colorGroup)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(card.isSelected ? .white : LineyTheme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: onOpen) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(card.isSelected ? .white : LineyTheme.secondaryText)
            .help(localized("canvas.card.openTab"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LineyTheme.chromeBackground.opacity(0.94))
        .gesture(
            DragGesture(coordinateSpace: .global)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    onDragCommit(value.translation)
                }
        )
    }

    private var minimizedSummary: some View {
        HStack(spacing: 10) {
            WorkspaceCanvasBadge(text: localizedFormat("canvas.card.activeCountFormat", card.activeSessionCount), tint: LineyTheme.success)
            Text(card.tab.layout == nil ? localized("canvas.card.noLiveLayout") : localized("canvas.card.collapsedLiveView"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LineyTheme.mutedText)
            Spacer(minLength: 0)
            Text(card.worktreePath.abbreviatedPath)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(LineyTheme.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let node = card.tab.layout {
            WorkspaceCanvasLiveNodeView(
                sessionController: card.controller,
                node: node,
                allowsInteraction: card.isSelected
            )
            .padding(10)
            .background(LineyTheme.paneBackground)
            .allowsHitTesting(card.isSelected)
            .overlay {
                if !card.isSelected {
                    inactiveOverlay
                }
            }
        }
    }

    private var inactiveOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.12))
    }

    private var cardBackground: Color {
        card.isSelected
            ? LineyTheme.panelRaised
            : LineyTheme.panelBackground
    }

    private var cardBorder: Color {
        (layout.colorGroup == .none ? (card.isSelected ? LineyTheme.accent : LineyTheme.border) : accentTint.opacity(card.isSelected ? 0.65 : 0.36))
    }

    private var shadowColor: Color {
        if card.isSelected {
            return accentTint.opacity(0.2)
        }
        if layout.isPinned {
            return accentTint.opacity(0.12)
        }
        return Color.black.opacity(0.18)
    }
}

private struct WorkspaceCanvasLiveNodeView: View {
    @ObservedObject var sessionController: WorkspaceSessionController
    let node: SessionLayoutNode
    let allowsInteraction: Bool

    var body: some View {
        switch node {
        case .pane(let leaf):
            if let session = sessionController.session(for: leaf.paneID) {
                WorkspaceCanvasTerminalPane(
                    session: session,
                    isFocused: sessionController.focusedPaneID == leaf.paneID,
                    allowsInteraction: allowsInteraction
                )
            } else {
                Color.clear
            }
        case .split(let split):
            GeometryReader { geometry in
                splitBody(split, in: geometry.size)
            }
        }
    }

    @ViewBuilder
    private func splitBody(_ split: PaneSplitNode, in size: CGSize) -> some View {
        let dividerThickness: CGFloat = 2
        let clampedFraction = min(max(split.fraction, 0.12), 0.88)

        if split.axis == .vertical {
            let firstWidth = max(160, (size.width - dividerThickness) * clampedFraction)
            let secondWidth = max(160, size.width - dividerThickness - firstWidth)

            HStack(spacing: 0) {
                WorkspaceCanvasLiveNodeView(
                    sessionController: sessionController,
                    node: split.first,
                    allowsInteraction: allowsInteraction
                )
                .frame(width: firstWidth)

                Rectangle()
                    .fill(LineyTheme.border)
                    .frame(width: dividerThickness)

                WorkspaceCanvasLiveNodeView(
                    sessionController: sessionController,
                    node: split.second,
                    allowsInteraction: allowsInteraction
                )
                .frame(width: secondWidth)
            }
        } else {
            let firstHeight = max(110, (size.height - dividerThickness) * clampedFraction)
            let secondHeight = max(110, size.height - dividerThickness - firstHeight)

            VStack(spacing: 0) {
                WorkspaceCanvasLiveNodeView(
                    sessionController: sessionController,
                    node: split.first,
                    allowsInteraction: allowsInteraction
                )
                .frame(height: firstHeight)

                Rectangle()
                    .fill(LineyTheme.border)
                    .frame(height: dividerThickness)

                WorkspaceCanvasLiveNodeView(
                    sessionController: sessionController,
                    node: split.second,
                    allowsInteraction: allowsInteraction
                )
                .frame(height: secondHeight)
            }
        }
    }
}

private struct WorkspaceCanvasTerminalPane: View {
    @ObservedObject var session: ShellSession
    let isFocused: Bool
    let allowsInteraction: Bool

    private var directoryLabel: String {
        session.effectiveWorkingDirectory.lastPathComponentValue
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.hasActiveProcess ? LineyTheme.success : LineyTheme.warning)
                    .frame(width: 6, height: 6)

                Text(session.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LineyTheme.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(directoryLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isFocused ? LineyTheme.panelRaised : LineyTheme.paneHeaderBackground)

            TerminalHostView(session: session)
                .background(LineyTheme.paneBackground)
                .allowsHitTesting(allowsInteraction)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isFocused ? LineyTheme.accent.opacity(0.4) : LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct WorkspaceCanvasBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )
    }
}

private struct GlobalCanvasBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [LineyTheme.appBackground, LineyTheme.canvasBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
