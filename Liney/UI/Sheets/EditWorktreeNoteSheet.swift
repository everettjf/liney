//
//  EditWorktreeNoteSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct EditWorktreeNoteSheet: View {
    let request: EditWorktreeNoteRequest
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @FocusState private var isNoteFocused: Bool

    init(request: EditWorktreeNoteRequest, onSubmit: @escaping (String) -> Void) {
        self.request = request
        self.onSubmit = onSubmit
        _note = State(initialValue: request.currentNote)
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("sheet.worktreeNote.title"))
                .font(.title2.weight(.semibold))

            Text(URL(fileURLWithPath: request.worktreePath).lastPathComponent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("sheet.worktreeNote.label"))
                    .font(.headline)

                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .focused($isNoteFocused)
            }

            HStack {
                if !request.currentNote.isEmpty {
                    Button {
                        note = ""
                        onSubmit("")
                        dismiss()
                    } label: {
                        Label(localized("sheet.worktreeNote.clear"), systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    onSubmit(note)
                    dismiss()
                } label: {
                    Label(localized("common.save"), systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async {
                isNoteFocused = true
            }
        }
    }
}
