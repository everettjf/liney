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
                Menu {
                    if state.availableTargets.isEmpty {
                        Text("No other worktrees")
                    } else {
                        ForEach(state.availableTargets) { target in
                            Button {
                                state.beginApply(to: target)
                            } label: {
                                if let branch = target.branch, !branch.isEmpty {
                                    Text("\(target.displayName) — \(branch)")
                                } else {
                                    Text(target.displayName)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .help("Apply these changes to another worktree")
                .disabled(state.changedFiles.isEmpty || state.availableTargets.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Diff")
            }
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
            case .result(let result):
                resultBody(result)
            }
        }
        .padding(24)
        .frame(width: 440)
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

            Text("\(preview.fileCount) of \(state.changedFiles.count) changed file(s) selected.")
                .font(.callout)

            fileSelectionList

            if preview.fileCount == 0 {
                Text(preview.detail.isEmpty ? "Select at least one file to apply." : preview.detail)
                    .font(.callout)
                    .foregroundStyle(LineyTheme.mutedText)
            } else if preview.appliesCleanly {
                Label("Applies cleanly", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LineyTheme.success)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Conflicts detected", systemImage: "exclamationmark.triangle.fill")
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
                        .frame(maxHeight: 120)
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

    private var fileSelectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(state.changedFiles) { file in
                    Toggle(isOn: Binding(
                        get: { state.applySelection.contains(file.id) },
                        set: { _ in state.toggleApplyFile(file.id) }
                    )) {
                        HStack(spacing: 8) {
                            Text(file.statusSymbol)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(file.status.color)
                                .frame(width: 14)
                            Text(file.displayPath)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
        .padding(8)
        .background(LineyTheme.canvasBackground, in: RoundedRectangle(cornerRadius: 6))
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
