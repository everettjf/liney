//
//  WorkspaceGroupEditorSheet.swift
//  Liney
//

import SwiftUI

struct WorkspaceGroupEditorSheet: View {
    let request: WorkspaceGroupEditorRequest
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private var title: String {
        switch request.mode {
        case .create:
            return localized("sheet.workspaceGroup.createTitle")
        case .rename:
            return localized("sheet.workspaceGroup.renameTitle")
        }
    }

    private var actionTitle: String {
        switch request.mode {
        case .create:
            return localized("sheet.workspaceGroup.createAction")
        case .rename:
            return localized("common.save")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            TextField(localized("sheet.workspaceGroup.placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(localized("common.cancel")) {
                    dismiss()
                }
                Button(actionTitle) {
                    onSubmit(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            name = request.initialName
        }
    }
}
