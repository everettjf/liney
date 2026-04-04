//
//  RenameWorkspaceSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

private let groupNameSuggestions: [String] = [
    "Payment System",
    "Infrastructure",
    "Side Projects",
    "Frontend",
    "Backend",
    "Microservices",
    "DevOps",
    "Mobile",
    "Libraries",
    "Experiments",
]

struct RenameWorkspaceSheet: View {
    let request: RenameWorkspaceRequest
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var showSuggestions = false

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private var sheetTitle: String {
        if request.isGroupCreation {
            return localized("sheet.createGroup.title")
        } else if request.isGroupRename {
            return localized("sheet.renameGroup.title")
        }
        return localized("sheet.renameWorkspace.title")
    }

    private var sheetPlaceholder: String {
        if request.isGroupCreation || request.isGroupRename {
            return localized("sheet.groupName.placeholder")
        }
        return localized("sheet.renameWorkspace.placeholder")
    }

    private var isGroupSheet: Bool {
        request.isGroupCreation || request.isGroupRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(sheetTitle)
                .font(.title2.weight(.semibold))

            TextField(sheetPlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)

            if isGroupSheet {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Button {
                            name = groupNameSuggestions.randomElement() ?? "Projects"
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "dice.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(localized("sheet.groupName.random"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSuggestions.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showSuggestions ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                Text(localized("sheet.groupName.presets"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .foregroundStyle(.secondary)

                    if showSuggestions {
                        FlowLayout(spacing: 6) {
                            ForEach(groupNameSuggestions, id: \.self) { suggestion in
                                Button {
                                    name = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            name == suggestion
                                                ? Color.accentColor.opacity(0.2)
                                                : Color.white.opacity(0.04),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule().strokeBorder(
                                                name == suggestion
                                                    ? Color.accentColor.opacity(0.5)
                                                    : Color.white.opacity(0.1),
                                                lineWidth: 1
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(name == suggestion ? .primary : .secondary)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    onSubmit(name)
                    dismiss()
                } label: {
                    Label(localized("common.save"), systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            name = request.currentName
            if request.isGroupCreation && name.isEmpty {
                name = groupNameSuggestions.randomElement() ?? "Projects"
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        let size: CGSize
        let offsets: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            offsets: offsets
        )
    }
}
