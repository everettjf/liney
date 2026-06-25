//
//  DiffWindowContentView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI
import YiTong

private enum DiffPresentationStyle: String {
    case split
    case unified
}

struct DiffWindowContentView: View {
    @ObservedObject var state: DiffWindowState
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var listSelection: String?
    @AppStorage("liney.diff.viewStyle") private var diffStyleRaw = DiffPresentationStyle.split.rawValue
    @AppStorage("liney.diff.zoom") private var zoomLevel: Double = 1.0
    @State private var isShowingCommitSheet = false
    @State private var commitMessage = ""

    private var diffStyle: DiffPresentationStyle {
        DiffPresentationStyle(rawValue: diffStyleRaw) ?? .split
    }

    init(state: DiffWindowState) {
        self.state = state
        _listSelection = State(initialValue: state.selectedFileID)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            fileListSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            diffDetail
        }
        .background(LineyTheme.appBackground)
        .safeAreaInset(edge: .top) {
            if let compareTarget = state.compareTarget {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x1")
                    Text("Comparing this worktree against \(compareTargetLabel(compareTarget))")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(LineyTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(LineyTheme.chromeBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LineyTheme.border).frame(height: 1)
                }
            }
        }
        .onChange(of: listSelection) { _, newValue in
            guard state.selectedFileID != newValue else { return }
            state.selectedFileID = newValue
            state.updateDocumentSelection(for: newValue)
        }
        .onChange(of: state.selectedFileID) { _, newValue in
            guard listSelection != newValue else { return }
            listSelection = newValue
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }

            ToolbarItem(placement: .primaryAction) {
                Picker("Diff Style", selection: $diffStyleRaw) {
                    Image(systemName: "square.split.2x1")
                        .tag(DiffPresentationStyle.split.rawValue)
                    Image(systemName: "text.justify.left")
                        .tag(DiffPresentationStyle.unified.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .help("Diff Style")
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    Button {
                        zoomLevel = max(0.5, zoomLevel - 0.1)
                        applyZoom()
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom Out (⌘-)")

                    Button {
                        zoomLevel = 1.0
                        applyZoom()
                    } label: {
                        Text("\(Int(zoomLevel * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .frame(minWidth: 36)
                    }
                    .help("Reset Zoom (⌘0)")

                    Button {
                        zoomLevel = min(3.0, zoomLevel + 0.1)
                        applyZoom()
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom In (⌘+)")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if state.compareTarget != nil {
                    Button {
                        state.endCompare()
                    } label: {
                        Label("Exit Compare", systemImage: "xmark.circle")
                    }
                    .help("Exit A/B compare and show changes vs HEAD")
                } else {
                    Menu {
                        if state.availableTargets.isEmpty {
                            Text("No other worktrees")
                        } else {
                            ForEach(state.availableTargets) { target in
                                Button {
                                    state.startCompare(with: target)
                                } label: {
                                    Text(compareTargetLabel(target))
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                    }
                    .help("Compare this worktree against another (A/B)")
                    .disabled(state.availableTargets.isEmpty)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if state.availableTargets.isEmpty {
                        Text("No other worktrees")
                    } else {
                        ForEach(state.availableTargets) { target in
                            Button {
                                state.beginApply(to: target)
                            } label: {
                                Text(compareTargetLabel(target))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .help("Apply these changes to another worktree")
                .disabled(state.compareTarget != nil || state.changedFiles.isEmpty || state.availableTargets.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Diff")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    commitMessage = ""
                    state.commitErrorMessage = nil
                    isShowingCommitSheet = true
                } label: {
                    Label("Commit", systemImage: "checkmark.circle")
                }
                .help("Commit all changes in this worktree")
                .disabled(state.changedFiles.isEmpty || state.worktreePath == nil || state.isCommitting)
            }
        }
        .sheet(isPresented: $isShowingCommitSheet) {
            DiffCommitSheet(
                state: state,
                message: $commitMessage,
                onCancel: { isShowingCommitSheet = false },
                onCommitted: { isShowingCommitSheet = false }
            )
        }
        .sheet(isPresented: applySheetBinding) {
            DiffApplySheet(state: state)
        }
    }

    private var applySheetBinding: Binding<Bool> {
        Binding(
            get: { state.applyPhase != .idle },
            set: { presented in
                if !presented { state.cancelApply() }
            }
        )
    }

    private func compareTargetLabel(_ target: WorktreeApplyTarget) -> String {
        if let branch = target.branch, !branch.isEmpty {
            return "\(target.displayName) — \(branch)"
        }
        return target.displayName
    }

    private var fileListSidebar: some View {
        List(selection: $listSelection) {
            ForEach(state.changedFiles) { file in
                DiffFileRow(file: file)
                    .tag(file.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if state.isLoadingFiles && state.changedFiles.isEmpty {
                ProgressView()
            } else if let loadErrorMessage = state.loadErrorMessage {
                ContentUnavailableView(
                    "Unable to Load Changes",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else if !state.isLoadingFiles && state.changedFiles.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text(state.emptyStateMessage)
                )
            }
        }
    }

    private var diffDetail: some View {
        Group {
            if state.isLoadingDocument && state.document == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = state.document {
                VStack(spacing: 0) {
                    DiffDocumentHeader(file: document.file)
                    DiffYiTongDocumentView(document: document, diffStyle: diffStyle)
                }
            } else if state.isLoadingFiles {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.changedFiles.isEmpty && state.loadErrorMessage == nil {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text(state.emptyStateMessage)
                )
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text",
                    description: Text("Choose a changed file from the sidebar.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineyTheme.appBackground)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                applyZoom()
            }
        }
        .onChange(of: state.document?.file.id) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                applyZoom()
            }
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.15)) {
            columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
        }
    }

    private func applyZoom() {
        DiffWindowManager.shared.applyZoom(zoomLevel)
    }
}

private struct DiffFileRow: View {
    let file: DiffChangedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(file.statusSymbol)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(file.status.color)
                    .frame(width: 14)

                Text(file.displayName)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if file.status == .renamed || file.status == .copied {
                    Text(file.status == .renamed ? "rename" : "copy")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(file.status.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(file.status.color.opacity(0.12), in: Capsule())
                }
            }

            if !file.directoryPath.isEmpty {
                Text(file.directoryPath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            if let oldPath = file.oldPath, let newPath = file.newPath, oldPath != newPath {
                Text("\(oldPath) -> \(newPath)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DiffDocumentHeader: View {
    let file: DiffChangedFile

    var body: some View {
        HStack(spacing: 10) {
            Text(file.statusSymbol)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(file.status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(file.status.color.opacity(0.12), in: Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.system(size: 14, weight: .semibold))
                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LineyTheme.chromeBackground.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LineyTheme.border)
                .frame(height: 1)
        }
    }
}

private struct DiffCommitSheet: View {
    @ObservedObject var state: DiffWindowState
    @Binding var message: String
    let onCancel: () -> Void
    let onCommitted: () -> Void

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subtitle: String {
        let count = state.changedFiles.count
        let fileText = count == 1 ? "1 file" : "\(count) files"
        let branchPrefix = state.branchName.isEmpty ? "" : "\(state.branchName) · "
        return "\(branchPrefix)\(fileText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Commit Changes")
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 380, minHeight: 110)
                    .padding(6)
                    .background(LineyTheme.canvasBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(LineyTheme.border)
                    )
                    .disabled(state.isCommitting)

                if message.isEmpty {
                    Text("Summary of changes…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }

            if let commitErrorMessage = state.commitErrorMessage {
                Text(commitErrorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(LineyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(state.isCommitting)

                Button {
                    Task {
                        if await state.commitAllChanges(message: message) {
                            onCommitted()
                        }
                    }
                } label: {
                    if state.isCommitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Commit")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isCommitting || trimmedMessage.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct DiffYiTongDocumentView: View {
    let document: DiffFileDocument
    let diffStyle: DiffPresentationStyle

    var body: some View {
        DiffView(
            document: yiTongDocument,
            configuration: yiTongConfiguration
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineyTheme.canvasBackground)
    }

    private var yiTongDocument: DiffDocument {
        return DiffDocument(
            patch: document.unifiedPatch,
            title: document.file.displayPath
        )
    }

    private var yiTongConfiguration: DiffConfiguration {
        DiffConfiguration(
            appearance: .automatic,
            style: diffStyle == .split ? .split : .unified,
            indicators: .bars,
            showsLineNumbers: true,
            showsChangeBackgrounds: true,
            wrapsLines: false,
            showsFileHeaders: false,
            inlineChangeStyle: .wordAlt,
            allowsSelection: true
        )
    }
}

private struct DiffApplySheet: View {
    @ObservedObject var state: DiffWindowState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch state.applyPhase {
            case .idle:
                EmptyView()
            case .working:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing changes…")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            case .preview(let preview):
                previewBody(preview)
            case .conflicts(let conflictState):
                conflictsBody(conflictState)
            case .result(let result):
                resultBody(result)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private func previewBody(_ preview: WorktreeApplyPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Apply to \(preview.target.displayName)", systemImage: "arrow.turn.down.right")
                .font(.headline)

            if let branch = preview.target.branch, !branch.isEmpty {
                Text(branch)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            Text("\(preview.fileCount) file(s) selected. Pick the hunks to apply:")
                .font(.callout)

            hunkSelectionList

            if preview.fileCount == 0 {
                Text(preview.detail.isEmpty ? "Select at least one hunk to apply." : preview.detail)
                    .font(.callout)
                    .foregroundStyle(LineyTheme.mutedText)
            } else if preview.appliesCleanly {
                Label("Applies cleanly", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LineyTheme.success)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Conflicts detected — a 3-way merge will be attempted", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(LineyTheme.warning)
                        .font(.callout)
                    if !preview.detail.isEmpty {
                        ScrollView {
                            Text(preview.detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(LineyTheme.mutedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                    }
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    state.cancelApply()
                }
                Spacer()
                if preview.fileCount == 0 {
                    Button("Apply") {}
                        .disabled(true)
                } else if preview.appliesCleanly {
                    Button("Apply") {
                        state.confirmApply(threeWay: false)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Apply with 3-way merge") {
                        state.confirmApply(threeWay: true)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)
        }
    }

    private var hunkSelectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.patchSections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: Binding(
                            get: { state.isSectionFullySelected(section) },
                            set: { _ in state.toggleSection(section) }
                        )) {
                            Text(section.path)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .toggleStyle(.checkbox)

                        ForEach(section.hunks) { hunk in
                            Toggle(isOn: Binding(
                                get: { state.selectedHunkIDs.contains(hunk.id) },
                                set: { _ in state.toggleHunk(hunk.id) }
                            )) {
                                Text(hunkLabel(hunk))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(LineyTheme.mutedText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .toggleStyle(.checkbox)
                            .padding(.leading, 18)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(8)
        .background(LineyTheme.canvasBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private func hunkLabel(_ hunk: PatchHunk) -> String {
        if hunk.isWholeFile {
            return hunk.header
        }
        return "\(hunk.header)  +\(hunk.addedCount) -\(hunk.removedCount)"
    }

    @ViewBuilder
    private func conflictsBody(_ conflictState: WorktreeConflictState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Resolve conflicts in \(conflictState.target.displayName)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LineyTheme.warning)
                .font(.headline)

            Text("The 3-way merge left \(conflictState.files.count) file(s) conflicted. Choose a side per file, or open the worktree to edit the conflict markers directly.")
                .font(.callout)
                .foregroundStyle(LineyTheme.mutedText)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(conflictState.files, id: \.self) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 8) {
                                Button("Use incoming") {
                                    state.resolveConflict(file: file, useTheirs: true)
                                }
                                Button("Keep target") {
                                    state.resolveConflict(file: file, useTheirs: false)
                                }
                            }
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(LineyTheme.canvasBackground, in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Leave markers & close") {
                    state.cancelApply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func resultBody(_ result: DiffApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if result.success {
                Label("Changes applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LineyTheme.success)
                    .font(.headline)
            } else {
                Label("Apply failed", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(LineyTheme.danger)
                    .font(.headline)
            }

            if !result.message.isEmpty {
                ScrollView {
                    Text(result.message)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
            }

            HStack {
                Spacer()
                Button("Done") {
                    state.cancelApply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private extension DiffFileStatus {
    var color: Color {
        switch self {
        case .modified:
            return LineyTheme.warning
        case .added:
            return LineyTheme.success
        case .deleted:
            return LineyTheme.danger
        case .renamed, .copied:
            return LineyTheme.accent
        case .unknown:
            return LineyTheme.mutedText
        }
    }
}
