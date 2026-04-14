//
//  CreateWorktreeSheet.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

struct CreateWorktreeSheet: View {
    let request: CreateWorktreeSheetRequest
    let onSubmit: (CreateWorktreeDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CreateWorktreeDraft
    @State private var parentDirectoryPath: String
    @FocusState private var isBranchFieldFocused: Bool

    init(request: CreateWorktreeSheetRequest, onSubmit: @escaping (CreateWorktreeDraft) -> Bool) {
        self.request = request
        self.onSubmit = onSubmit

        let branchName = (request.repositoryRoot as NSString).lastPathComponent

        if request.isRemote {
            let parentDirectoryPath = (request.repositoryRoot as NSString).deletingLastPathComponent
            let directoryPath = (parentDirectoryPath as NSString).appendingPathComponent(branchName)
            _draft = State(
                initialValue: CreateWorktreeDraft(
                    directoryPath: directoryPath,
                    branchName: branchName
                )
            )
            _parentDirectoryPath = State(initialValue: parentDirectoryPath)
        } else {
            let parentDirectoryPath = URL(fileURLWithPath: request.repositoryRoot)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path

            _draft = State(
                initialValue: CreateWorktreeDraft(
                    directoryPath: URL(fileURLWithPath: parentDirectoryPath)
                        .appendingPathComponent(branchName)
                        .standardizedFileURL
                        .path,
                    branchName: branchName
                )
            )
            _parentDirectoryPath = State(initialValue: parentDirectoryPath)
        }
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var validationMessage: String? {
        if draft.normalizedDirectoryPath.isEmpty {
            return localized("sheet.worktree.validation.directoryRequired")
        }
        if draft.normalizedBranchName.isEmpty {
            return localized("sheet.worktree.validation.branchRequired")
        }
        if draft.normalizedBranchName.contains(" ") {
            return localized("sheet.worktree.validation.branchNoSpaces")
        }
        if !request.isRemote && FileManager.default.fileExists(atPath: draft.normalizedDirectoryPath) {
            return localized("sheet.worktree.validation.pathExists")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("sheet.worktree.title"))
                .font(.title2.weight(.semibold))

            Text(request.repositoryRoot.abbreviatedPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                if request.isRemote {
                    Text(localized("sheet.worktree.directoryPath"))
                        .font(.headline)
                    TextField(localized("sheet.worktree.pathPlaceholder"), text: $draft.directoryPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                } else {
                    HStack {
                        Text(localized("sheet.worktree.directoryPath"))
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 6) {
                            directoryActionButton(
                                systemImage: "folder.badge.gearshape",
                                help: localized("sheet.worktree.chooseParentDirectory"),
                                action: chooseParentDirectory
                            )
                            directoryActionButton(
                                systemImage: "arrow.up.forward.app",
                                help: localized("sheet.worktree.openInFinder"),
                                action: openDirectoryInFinder
                            )
                            .disabled(draft.directoryPath.isEmpty)
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("sheet.worktree.targetFolderPreview"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text(draft.directoryPath.isEmpty ? localized("sheet.worktree.pathPlaceholder") : draft.directoryPath)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(draft.directoryPath.isEmpty ? .tertiary : .primary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor).opacity(0.92),
                                Color(nsColor: .controlBackgroundColor).opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }

                Text(localized("sheet.worktree.branchName"))
                    .font(.headline)
                TextField(localized("sheet.worktree.branchPlaceholder"), text: $draft.branchName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isBranchFieldFocused)

                Toggle(localized("sheet.worktree.createNewBranch"), isOn: $draft.createNewBranch)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    if onSubmit(draft) {
                        dismiss()
                    }
                } label: {
                    Label(localized("common.create"), systemImage: "plus")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async {
                isBranchFieldFocused = true
                DispatchQueue.main.async {
                    moveBranchInsertionPointToEnd()
                }
            }
        }
        .onChange(of: draft.branchName) { _, newValue in
            updateSuggestedDirectoryPath(for: newValue)
        }
    }

    private func chooseParentDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("common.choose")
        panel.directoryURL = URL(fileURLWithPath: parentDirectoryPath)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        parentDirectoryPath = url.standardizedFileURL.path
        updateSuggestedDirectoryPath(for: draft.branchName)
    }

    private func updateSuggestedDirectoryPath(for branchName: String) {
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft.directoryPath = ""
        } else {
            let leafName = trimmed.replacingOccurrences(of: "/", with: "-")
            if request.isRemote {
                draft.directoryPath = (parentDirectoryPath as NSString).appendingPathComponent(leafName)
            } else {
                draft.directoryPath = URL(fileURLWithPath: parentDirectoryPath)
                    .appendingPathComponent(leafName)
                    .standardizedFileURL
                    .path
            }
        }
    }

    private func openDirectoryInFinder() {
        let normalizedPath = URL(fileURLWithPath: draft.directoryPath)
            .standardizedFileURL
            .path

        guard !normalizedPath.isEmpty else { return }

        let targetURL = URL(fileURLWithPath: normalizedPath)
        if FileManager.default.fileExists(atPath: normalizedPath) {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            return
        }

        NSWorkspace.shared.open(targetURL.deletingLastPathComponent())
    }

    @ViewBuilder
    private func directoryActionButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .help(help)
    }

    private func moveBranchInsertionPointToEnd() {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let location = (draft.branchName as NSString).length
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }
}
