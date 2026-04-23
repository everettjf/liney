//
//  TerminalScrollbarOverlay.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct TerminalScrollbarOverlay: View {
    @ObservedObject var session: ShellSession

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragAnchorOffset: UInt64?
    @State private var dragAnchorThumbTop: CGFloat?

    private var viewport: TerminalViewportStatus? {
        session.surfaceStatus.viewport
    }

    private var isScrollable: Bool {
        guard let v = viewport else { return false }
        return v.total > v.length && v.length > 0
    }

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let thumbMetrics = computeThumbMetrics(trackHeight: trackHeight)

            ZStack(alignment: .top) {
                Color.clear
                if let thumb = thumbMetrics {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(isDragging ? 0.55 : (isHovering ? 0.40 : 0.22)))
                        .frame(width: 5, height: thumb.height)
                        .padding(.leading, 1)
                        .offset(y: thumb.top)
                        .animation(.easeOut(duration: 0.1), value: isDragging)
                        .animation(.easeOut(duration: 0.1), value: isHovering)
                }
            }
            .frame(width: 7, height: trackHeight, alignment: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        handleDrag(value: value, trackHeight: trackHeight, thumb: thumbMetrics)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragAnchorOffset = nil
                        dragAnchorThumbTop = nil
                    }
            )
        }
        .frame(width: 7)
        .opacity(isScrollable ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: isScrollable)
        .allowsHitTesting(isScrollable)
    }

    private struct ThumbMetrics {
        var top: CGFloat
        var height: CGFloat
    }

    private func computeThumbMetrics(trackHeight: CGFloat) -> ThumbMetrics? {
        guard let v = viewport, v.total > 0, v.length > 0, trackHeight > 4 else { return nil }
        let total = Double(v.total)
        let length = Double(v.length)
        let offset = Double(v.offset)
        let maxOffset = max(total - length, 1)

        let fraction = min(max(length / total, 0), 1)
        let minThumb: CGFloat = 24
        let rawHeight = trackHeight * CGFloat(fraction)
        let height = min(max(rawHeight, minThumb), trackHeight)
        let available = max(trackHeight - height, 0)
        let progress = min(max(offset / maxOffset, 0), 1)
        let top = available * CGFloat(progress)
        return ThumbMetrics(top: top, height: height)
    }

    private func handleDrag(value: DragGesture.Value, trackHeight: CGFloat, thumb: ThumbMetrics?) {
        guard let v = viewport, v.total > v.length, let thumb else { return }
        let available = max(trackHeight - thumb.height, 1)
        let maxOffset = max(Int64(v.total) - Int64(v.length), 1)

        if dragAnchorOffset == nil {
            isDragging = true
            let pressY = value.startLocation.y
            let thumbRange = thumb.top...(thumb.top + thumb.height)
            if thumbRange.contains(pressY) {
                dragAnchorThumbTop = thumb.top
            } else {
                let desiredTop = min(max(pressY - thumb.height / 2, 0), available)
                dragAnchorThumbTop = desiredTop
                applyThumbTop(desiredTop, available: available, maxOffset: maxOffset)
            }
            dragAnchorOffset = session.surfaceStatus.viewport?.offset
        }

        guard let anchorTop = dragAnchorThumbTop, let anchorOffset = dragAnchorOffset else { return }
        let newTop = min(max(anchorTop + value.translation.height, 0), available)
        let progress = Double(newTop) / Double(available)
        let targetOffset = Int64((progress * Double(maxOffset)).rounded())
        let delta = targetOffset - Int64(anchorOffset)
        if delta != 0 {
            session.scrollByLines(Int(delta))
            dragAnchorOffset = UInt64(max(Int64(0), min(targetOffset, maxOffset)))
            dragAnchorThumbTop = newTop
        }
    }

    private func applyThumbTop(_ top: CGFloat, available: CGFloat, maxOffset: Int64) {
        guard available > 0 else { return }
        let progress = Double(top) / Double(available)
        let targetOffset = Int64((progress * Double(maxOffset)).rounded())
        let current = Int64(session.surfaceStatus.viewport?.offset ?? 0)
        let delta = targetOffset - current
        if delta != 0 {
            session.scrollByLines(Int(delta))
        }
    }
}
