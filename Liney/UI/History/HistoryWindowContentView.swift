//
//  HistoryWindowContentView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI
import YiTong

private enum HistoryDiffPresentationStyle: String {
    case split
    case unified
}

struct HistoryWindowContentView: View {
    @ObservedObject var state: HistoryWindowState
    @State private var commitSelection: String?
    @State private var fileSelection: String?
    @AppStorage("liney.history.viewStyle") private var diffStyleRaw = HistoryDiffPresentationStyle.split.rawValue

    private var diffStyle: HistoryDiffPresentationStyle {
        HistoryDiffPresentationStyle(rawValue: diffStyleRaw) ?? .split
    }

    init(state: HistoryWindowState) {
        self.state = state
        _commitSelection = State(initialValue: state.selectedCommitID)
        _fileSelection = State(initialValue: state.selectedFileID)
    }

    var body: some View {
        HSplitView {
            commitListPanel
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
            if case .blame = state.viewMode {
                blamePanel
                    .frame(minWidth: 500)
            } else {
                fileListPanel
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                diffDetailPanel
                    .frame(minWidth: 400)
            }
        }
        .background(LineyTheme.appBackground)
        .onChange(of: commitSelection) { _, newValue in
            guard state.selectedCommitID != newValue else { return }
            state.selectedCommitID = newValue
            state.updateCommitSelection(for: newValue)
            fileSelection = nil
        }
        .onChange(of: state.selectedCommitID) { _, newValue in
            guard commitSelection != newValue else { return }
            commitSelection = newValue
        }
        .onChange(of: fileSelection) { _, newValue in
            guard state.selectedFileID != newValue else { return }
            state.selectedFileID = newValue
            state.updateDocumentSelection(for: newValue)
        }
        .onChange(of: state.selectedFileID) { _, newValue in
            guard fileSelection != newValue else { return }
            fileSelection = newValue
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                viewModeBackButton
            }

            ToolbarItemGroup(placement: .principal) {
                branchPicker
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if state.rangeStartCommitID != nil {
                    Button {
                        state.rangeStartCommitID = nil
                    } label: {
                        Text("Cancel Range")
                            .font(.system(size: 11))
                    }
                    .help("Cancel range comparison")
                }

                Picker("Diff Style", selection: $diffStyleRaw) {
                    Image(systemName: "square.split.2x1")
                        .tag(HistoryDiffPresentationStyle.split.rawValue)
                    Image(systemName: "text.justify.left")
                        .tag(HistoryDiffPresentationStyle.unified.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .help("Diff Style")

                Button {
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    // MARK: - Back Button

    @ViewBuilder
    private var viewModeBackButton: some View {
        switch state.viewMode {
        case .commitHistory:
            EmptyView()
        case .fileHistory(let path):
            Button {
                state.exitFileHistory()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            .help("Back to full history")
        case .blame(let path, _):
            Button {
                state.exitBlame()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Blame: \(URL(fileURLWithPath: path).lastPathComponent)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            .help("Exit blame view")
        case .rangeComparison(let from, let to):
            Button {
                state.exitRangeComparison()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("\(String(from.prefix(7)))..\(String(to.prefix(7)))")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .help("Exit range comparison")
        }
    }

    // MARK: - Branch Picker

    @ViewBuilder
    private var branchPicker: some View {
        if !state.branches.isEmpty, case .commitHistory = state.viewMode {
            Picker("Branch", selection: Binding(
                get: { state.selectedBranch ?? state.branchName },
                set: { newValue in
                    let branch = newValue == state.branchName ? nil : newValue
                    state.switchBranch(branch)
                }
            )) {
                Text(state.branchName)
                    .tag(state.branchName)
                Divider()
                ForEach(state.branches.filter { $0 != state.branchName }, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
            .frame(maxWidth: 200)
        }
    }

    // MARK: - Commit List Panel

    private var commitListPanel: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LineyTheme.mutedText)
                    .font(.system(size: 12))
                TextField("Search commits...", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LineyTheme.mutedText)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LineyTheme.chromeBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(LineyTheme.border).frame(height: 1)
            }

            // Range comparison indicator
            if let rangeStart = state.rangeStartCommitID {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                    Text("Select end commit for range: \(String(rangeStart.prefix(7)))...")
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(LineyTheme.accent.opacity(0.15))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LineyTheme.border).frame(height: 1)
                }
            }

            // Commit list
            List(selection: $commitSelection) {
                ForEach(state.filteredCommits) { commit in
                    HistoryCommitRow(
                        commit: commit,
                        isRangeStart: commit.id == state.rangeStartCommitID
                    )
                    .tag(commit.id)
                    .onAppear {
                        state.loadMoreCommitsIfNeeded(currentCommitID: commit.id)
                    }
                    .contextMenu {
                        commitContextMenu(for: commit)
                    }
                }

                if state.isLoadingCommits && !state.commits.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if state.isLoadingCommits && state.commits.isEmpty {
                    ProgressView()
                } else if let loadErrorMessage = state.loadErrorMessage {
                    ContentUnavailableView(
                        "Unable to Load History",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadErrorMessage)
                    )
                } else if !state.isLoadingCommits && state.filteredCommits.isEmpty && !state.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No commits match \"\(state.searchQuery)\".")
                    )
                } else if !state.isLoadingCommits && state.commits.isEmpty {
                    ContentUnavailableView(
                        "No Commits",
                        systemImage: "clock",
                        description: Text(state.emptyStateMessage)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func commitContextMenu(for commit: GitHistoryCommit) -> some View {
        Button("Copy Commit Hash") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
        }

        Button("Copy Short Hash") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.shortHash, forType: .string)
        }

        Divider()

        if state.rangeStartCommitID == nil {
            Button("Compare from Here...") {
                state.startRangeComparison(fromCommitID: commit.hash)
            }
        } else {
            Button("Compare to Here") {
                state.selectedCommitID = commit.id
                state.completeRangeComparison(toCommitID: commit.hash)
            }
        }
    }

    // MARK: - File List Panel

    private var fileListPanel: some View {
        VStack(spacing: 0) {
            // Commit detail header
            if let commit = selectedCommit {
                HistoryCommitDetailHeader(commit: commit)
            }

            List(selection: $fileSelection) {
                ForEach(state.changedFiles) { file in
                    HistoryFileRow(file: file)
                        .tag(file.id)
                        .contextMenu {
                            fileContextMenu(for: file)
                        }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if state.selectedCommitID == nil && !state.isLoadingCommits {
                    ContentUnavailableView(
                        "Select a Commit",
                        systemImage: "arrow.left.circle",
                        description: Text("Choose a commit to see its changes.")
                    )
                } else if state.isLoadingFiles && state.changedFiles.isEmpty {
                    ProgressView()
                } else if !state.isLoadingFiles && state.changedFiles.isEmpty && state.selectedCommitID != nil {
                    ContentUnavailableView(
                        "No Changes",
                        systemImage: "checkmark.circle",
                        description: Text("This commit has no file changes.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(for file: DiffChangedFile) -> some View {
        let filePath = file.newPath ?? file.oldPath ?? file.displayPath

        Button("View File History") {
            state.showFileHistory(filePath: filePath)
        }

        if let commit = selectedCommit, file.status != .deleted {
            Button("View Blame") {
                state.showBlame(filePath: filePath, commit: commit.hash)
            }
        }

        Divider()

        Button("Copy File Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(filePath, forType: .string)
        }
    }

    // MARK: - Blame Panel

    private var blamePanel: some View {
        VStack(spacing: 0) {
            if case .blame(let path, let commit) = state.viewMode {
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(LineyTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 14, weight: .semibold))
                        Text("Blame at \(String(commit.prefix(7)))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LineyTheme.mutedText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LineyTheme.chromeBackground.opacity(0.96))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LineyTheme.border).frame(height: 1)
                }
            }

            if state.isLoadingBlame {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.blameLines.isEmpty {
                ContentUnavailableView(
                    "No Blame Data",
                    systemImage: "person.text.rectangle",
                    description: Text("Unable to load blame information.")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.blameLines) { line in
                            HistoryBlameLineRow(line: line)
                        }
                    }
                }
                .background(LineyTheme.canvasBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Diff Detail Panel

    private var diffDetailPanel: some View {
        Group {
            if state.isLoadingDocument && state.document == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = state.document {
                VStack(spacing: 0) {
                    HistoryDiffDocumentHeader(file: document.file, commit: selectedCommit)
                    HistoryYiTongDocumentView(document: document, diffStyle: diffStyle)
                }
            } else if state.isLoadingFiles {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.selectedCommitID == nil {
                ContentUnavailableView(
                    "Select a Commit",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose a commit from the history to view changes.")
                )
            } else if state.changedFiles.isEmpty && !state.isLoadingFiles {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("This commit has no file changes.")
                )
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text",
                    description: Text("Choose a changed file to view its diff.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineyTheme.appBackground)
    }

    private var selectedCommit: GitHistoryCommit? {
        guard let id = state.selectedCommitID else { return nil }
        return state.commits.first { $0.id == id }
    }
}

// MARK: - Commit Row

private struct HistoryCommitRow: View {
    let commit: GitHistoryCommit
    var isRangeStart: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(commit.subject)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if commit.isMergeCommit {
                    Text("merge")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LineyTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LineyTheme.accent.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 6) {
                Text(commit.shortHash)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LineyTheme.accent)

                Text(commit.authorName)
                    .font(.system(size: 11))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if !commit.statsDescription.isEmpty {
                    Text(commit.statsDescription)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                }

                Text(commit.relativeDate)
                    .font(.system(size: 10))
                    .foregroundStyle(LineyTheme.mutedText)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, isRangeStart ? 2 : 0)
        .overlay(alignment: .leading) {
            if isRangeStart {
                Rectangle()
                    .fill(LineyTheme.accent)
                    .frame(width: 3)
            }
        }
    }
}

// MARK: - Commit Detail Header

private struct HistoryCommitDetailHeader: View {
    let commit: GitHistoryCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.subject)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(3)

            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(.system(size: 11))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(4)
            }

            HStack(spacing: 8) {
                Text(commit.shortHash)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LineyTheme.accent)

                Text(commit.authorName)
                    .font(.system(size: 10))
                    .foregroundStyle(LineyTheme.mutedText)

                Text("<\(commit.authorEmail)>")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
                    .lineLimit(1)

                Spacer()

                Text(commit.formattedDate)
                    .font(.system(size: 10))
                    .foregroundStyle(LineyTheme.mutedText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LineyTheme.chromeBackground.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LineyTheme.border).frame(height: 1)
        }
    }
}

// MARK: - File Row

private struct HistoryFileRow: View {
    let file: DiffChangedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(file.statusSymbol)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(file.status.historyColor)
                    .frame(width: 14)

                Text(file.displayName)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if file.status == .renamed || file.status == .copied {
                    Text(file.status == .renamed ? "rename" : "copy")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(file.status.historyColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(file.status.historyColor.opacity(0.12), in: Capsule())
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

// MARK: - Blame Line Row

private struct HistoryBlameLineRow: View {
    let line: GitBlameLine

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text("\(line.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LineyTheme.mutedText)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 8)

            // Blame info
            HStack(spacing: 6) {
                Text(line.shortHash)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LineyTheme.accent)
                    .frame(width: 56, alignment: .leading)

                Text(line.author)
                    .font(.system(size: 10))
                    .foregroundStyle(LineyTheme.mutedText)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(1)

                Text(line.date)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LineyTheme.mutedText)
                    .frame(width: 74, alignment: .leading)
            }
            .frame(width: 250)
            .padding(.trailing, 8)

            // Separator
            Rectangle()
                .fill(LineyTheme.border)
                .frame(width: 1)
                .padding(.vertical, 2)

            // Code content
            Text(line.lineContent)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(line.id % 2 == 0 ? LineyTheme.canvasBackground : LineyTheme.canvasBackground.opacity(0.7))
    }
}

// MARK: - Diff Document Header

private struct HistoryDiffDocumentHeader: View {
    let file: DiffChangedFile
    let commit: GitHistoryCommit?

    var body: some View {
        HStack(spacing: 10) {
            Text(file.statusSymbol)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(file.status.historyColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(file.status.historyColor.opacity(0.12), in: Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 8) {
                    if !file.directoryPath.isEmpty {
                        Text(file.directoryPath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(LineyTheme.mutedText)
                    }
                    if let commit {
                        Text(commit.shortHash)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LineyTheme.accent)
                    }
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

// MARK: - YiTong Diff View

private struct HistoryYiTongDocumentView: View {
    let document: DiffFileDocument
    let diffStyle: HistoryDiffPresentationStyle

    var body: some View {
        DiffView(
            document: yiTongDocument,
            configuration: yiTongConfiguration
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineyTheme.canvasBackground)
    }

    private var yiTongDocument: DiffDocument {
        DiffDocument(
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

// MARK: - Color Extension

private extension DiffFileStatus {
    var historyColor: Color {
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
