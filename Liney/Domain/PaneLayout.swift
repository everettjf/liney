//
//  PaneLayout.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

enum PaneSplitAxis: String, Codable, CaseIterable {
    case vertical
    case horizontal

    var title: String {
        switch self {
        case .vertical:
            return "Vertical"
        case .horizontal:
            return "Horizontal"
        }
    }
}

enum PaneFocusDirection: String, Codable, CaseIterable {
    case left
    case right
    case up
    case down
}

enum PaneSplitPlacement {
    case before
    case after
}

struct PaneLeaf: Codable, Equatable, Hashable {
    var paneID: UUID
}

struct PaneSplitNode: Codable, Equatable, Hashable {
    var id: UUID
    var axis: PaneSplitAxis
    var fraction: Double
    var first: SessionLayoutNode
    var second: SessionLayoutNode

    init(
        id: UUID = UUID(),
        axis: PaneSplitAxis,
        fraction: Double = 0.5,
        first: SessionLayoutNode,
        second: SessionLayoutNode
    ) {
        self.id = id
        self.axis = axis
        self.fraction = fraction
        self.first = first
        self.second = second
    }
}

indirect enum SessionLayoutNode: Codable, Equatable, Hashable {
    case pane(PaneLeaf)
    case split(PaneSplitNode)

    private enum CodingKeys: String, CodingKey {
        case kind
        case pane
        case split
    }

    private enum Kind: String, Codable {
        case pane
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pane:
            self = .pane(try container.decode(PaneLeaf.self, forKey: .pane))
        case .split:
            self = .split(try container.decode(PaneSplitNode.self, forKey: .split))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let pane):
            try container.encode(Kind.pane, forKey: .kind)
            try container.encode(pane, forKey: .pane)
        case .split(let split):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(split, forKey: .split)
        }
    }

    var paneIDs: [UUID] {
        switch self {
        case .pane(let leaf):
            return [leaf.paneID]
        case .split(let split):
            return split.first.paneIDs + split.second.paneIDs
        }
    }

    var firstPaneID: UUID? {
        switch self {
        case .pane(let leaf):
            return leaf.paneID
        case .split(let split):
            return split.first.firstPaneID ?? split.second.firstPaneID
        }
    }

    var lastPaneID: UUID? {
        switch self {
        case .pane(let leaf):
            return leaf.paneID
        case .split(let split):
            return split.second.lastPaneID ?? split.first.lastPaneID
        }
    }

    mutating func split(
        paneID: UUID,
        axis: PaneSplitAxis,
        newPaneID: UUID,
        fraction: Double = 0.5,
        placement: PaneSplitPlacement = .after
    ) -> Bool {
        switch self {
        case .pane(let leaf):
            guard leaf.paneID == paneID else { return false }
            let existing = SessionLayoutNode.pane(PaneLeaf(paneID: paneID))
            let inserted = SessionLayoutNode.pane(PaneLeaf(paneID: newPaneID))
            self = .split(
                PaneSplitNode(
                    axis: axis,
                    fraction: fraction,
                    first: placement == .before ? inserted : existing,
                    second: placement == .before ? existing : inserted
                )
            )
            return true
        case .split(var split):
            if split.first.split(
                paneID: paneID,
                axis: axis,
                newPaneID: newPaneID,
                fraction: fraction,
                placement: placement
            ) {
                self = .split(split)
                return true
            }
            if split.second.split(
                paneID: paneID,
                axis: axis,
                newPaneID: newPaneID,
                fraction: fraction,
                placement: placement
            ) {
                self = .split(split)
                return true
            }
            return false
        }
    }

    mutating func updateFraction(splitID: UUID, fraction: Double) -> Bool {
        switch self {
        case .pane:
            return false
        case .split(var split):
            if split.id == splitID {
                split.fraction = min(max(fraction, 0.12), 0.88)
                self = .split(split)
                return true
            }
            if split.first.updateFraction(splitID: splitID, fraction: fraction) {
                self = .split(split)
                return true
            }
            if split.second.updateFraction(splitID: splitID, fraction: fraction) {
                self = .split(split)
                return true
            }
            return false
        }
    }

    mutating func resizeSplit(containing paneID: UUID, toward direction: PaneFocusDirection, amount: UInt16) -> Bool {
        let axis: PaneSplitAxis = switch direction {
        case .left, .right: .vertical
        case .up, .down: .horizontal
        }
        guard let splitID = nearestSplitID(containing: paneID, axis: axis) else { return false }
        let rawDelta = max(Double(amount), 1) / 320
        let delta = min(max(rawDelta, 0.02), 0.16)
        switch direction {
        case .left, .up:
            return adjustFraction(splitID: splitID, delta: -delta)
        case .right, .down:
            return adjustFraction(splitID: splitID, delta: delta)
        }
    }

    mutating func removePane(_ paneID: UUID) -> Bool {
        guard let updated = removingPane(paneID) else {
            return true
        }
        let didChange = updated != self
        self = updated
        return didChange
    }

    func nextPane(after paneID: UUID) -> UUID? {
        let panes = paneIDs
        guard let index = panes.firstIndex(of: paneID) else { return panes.first }
        return panes[(index + 1) % panes.count]
    }

    func previousPane(before paneID: UUID) -> UUID? {
        let panes = paneIDs
        guard let index = panes.firstIndex(of: paneID) else { return panes.first }
        let nextIndex = (index - 1 + panes.count) % panes.count
        return panes[nextIndex]
    }

    func paneID(in direction: PaneFocusDirection, from paneID: UUID) -> UUID? {
        guard let path = pathToPane(paneID) else { return nil }
        for step in path.reversed() {
            switch direction {
            case .left:
                if step.axis == .vertical, step.side == .second {
                    return step.sibling.lastPaneID
                }
            case .right:
                if step.axis == .vertical, step.side == .first {
                    return step.sibling.firstPaneID
                }
            case .up:
                if step.axis == .horizontal, step.side == .second {
                    return step.sibling.lastPaneID
                }
            case .down:
                if step.axis == .horizontal, step.side == .first {
                    return step.sibling.firstPaneID
                }
            }
        }
        return nil
    }

    mutating func equalizeSplits() {
        switch self {
        case .pane:
            return
        case .split(var split):
            let firstCount = Double(split.first.paneIDs.count)
            let secondCount = Double(split.second.paneIDs.count)
            split.fraction = firstCount / (firstCount + secondCount)
            split.first.equalizeSplits()
            split.second.equalizeSplits()
            self = .split(split)
        }
    }

    private func removingPane(_ paneID: UUID) -> SessionLayoutNode? {
        switch self {
        case .pane(let leaf):
            return leaf.paneID == paneID ? nil : self
        case .split(let split):
            let first = split.first.removingPane(paneID)
            let second = split.second.removingPane(paneID)

            switch (first, second) {
            case (nil, nil):
                return nil
            case (.some(let remaining), nil):
                return remaining
            case (nil, .some(let remaining)):
                return remaining
            case (.some(let firstNode), .some(let secondNode)):
                return .split(
                    PaneSplitNode(
                        id: split.id,
                        axis: split.axis,
                        fraction: split.fraction,
                        first: firstNode,
                        second: secondNode
                    )
                )
            }
        }
    }

    private enum PathSide {
        case first
        case second
    }

    private struct PathStep {
        var splitID: UUID
        var axis: PaneSplitAxis
        var side: PathSide
        var sibling: SessionLayoutNode
    }

    private mutating func adjustFraction(splitID: UUID, delta: Double) -> Bool {
        switch self {
        case .pane:
            return false
        case .split(var split):
            if split.id == splitID {
                split.fraction = min(max(split.fraction + delta, 0.12), 0.88)
                self = .split(split)
                return true
            }
            if split.first.adjustFraction(splitID: splitID, delta: delta) {
                self = .split(split)
                return true
            }
            if split.second.adjustFraction(splitID: splitID, delta: delta) {
                self = .split(split)
                return true
            }
            return false
        }
    }

    private func nearestSplitID(containing paneID: UUID, axis: PaneSplitAxis) -> UUID? {
        pathToPane(paneID)?
            .reversed()
            .first(where: { $0.axis == axis })?
            .splitID
    }

    private func pathToPane(_ paneID: UUID) -> [PathStep]? {
        switch self {
        case .pane(let leaf):
            return leaf.paneID == paneID ? [] : nil
        case .split(let split):
            if let nested = split.first.pathToPane(paneID) {
                return [PathStep(splitID: split.id, axis: split.axis, side: .first, sibling: split.second)] + nested
            }
            if let nested = split.second.pathToPane(paneID) {
                return [PathStep(splitID: split.id, axis: split.axis, side: .second, sibling: split.first)] + nested
            }
            return nil
        }
    }
}
