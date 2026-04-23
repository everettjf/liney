//
//  SplitNodeView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct SplitNodeView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var sessionController: WorkspaceSessionController
    let node: SessionLayoutNode

    var body: some View {
        Group {
            if let zoomedPaneID = workspace.zoomedPaneID {
                if let session = sessionController.session(for: zoomedPaneID) {
                    TerminalPaneView(workspace: workspace, sessionController: sessionController, session: session, paneID: zoomedPaneID)
                        .id(zoomedPaneID)
                } else {
                    Color.clear
                }
            } else {
                switch node {
                case .pane(let leaf):
                    if let session = sessionController.session(for: leaf.paneID) {
                        TerminalPaneView(workspace: workspace, sessionController: sessionController, session: session, paneID: leaf.paneID)
                            .id(leaf.paneID)
                    } else {
                        Color.clear
                    }
                case .split(let split):
                    GeometryReader { geometry in
                        splitBody(split, in: geometry.size)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func splitBody(_ split: PaneSplitNode, in size: CGSize) -> some View {
        let dividerThickness: CGFloat = 6
        let clampedFraction = min(max(split.fraction, 0.12), 0.88)
        let availableWidth = max(size.width - dividerThickness, 1)
        let availableHeight = max(size.height - dividerThickness, 1)

        if split.axis == .vertical {
            let firstWidth = max(120, (size.width - dividerThickness) * clampedFraction)
            let secondWidth = max(120, size.width - dividerThickness - firstWidth)

            HStack(spacing: 0) {
                SplitNodeView(workspace: workspace, sessionController: sessionController, node: split.first)
                    .frame(width: firstWidth)
                SplitDivider(
                    axis: .vertical,
                    fraction: clampedFraction,
                    availableLength: availableWidth
                ) { fraction in
                    workspace.updateSplitFraction(splitID: split.id, fraction: fraction)
                }
                    .frame(width: dividerThickness)
                SplitNodeView(workspace: workspace, sessionController: sessionController, node: split.second)
                    .frame(width: secondWidth)
            }
        } else {
            let firstHeight = max(90, (size.height - dividerThickness) * clampedFraction)
            let secondHeight = max(90, size.height - dividerThickness - firstHeight)

            VStack(spacing: 0) {
                SplitNodeView(workspace: workspace, sessionController: sessionController, node: split.first)
                    .frame(height: firstHeight)
                SplitDivider(
                    axis: .horizontal,
                    fraction: clampedFraction,
                    availableLength: availableHeight
                ) { fraction in
                    workspace.updateSplitFraction(splitID: split.id, fraction: fraction)
                }
                    .frame(height: dividerThickness)
                SplitNodeView(workspace: workspace, sessionController: sessionController, node: split.second)
                    .frame(height: secondHeight)
            }
        }
    }
}

private struct SplitDivider: View {
    let axis: PaneSplitAxis
    let fraction: Double
    let availableLength: CGFloat
    let onUpdate: (Double) -> Void

    @State private var dragStartFraction: Double?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: axis == .vertical ? 4 : 44, height: axis == .horizontal ? 4 : 44)
            Capsule(style: .continuous)
                .fill(LineyTheme.strongBorder)
                .frame(width: axis == .vertical ? 2 : 16, height: axis == .horizontal ? 2 : 16)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let startFraction = dragStartFraction ?? fraction
                    if dragStartFraction == nil {
                        dragStartFraction = fraction
                    }
                    let delta = axis == .vertical
                        ? value.translation.width / max(availableLength, 1)
                        : value.translation.height / max(availableLength, 1)
                    onUpdate(startFraction + delta)
                }
                .onEnded { _ in
                    dragStartFraction = nil
                }
        )
    }
}
