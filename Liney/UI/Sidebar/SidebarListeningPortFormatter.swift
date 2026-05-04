//
//  SidebarListeningPortFormatter.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Formats a list of listening ports into a compact sidebar badge string.
///
/// `[3000]` → `:3000`
/// `[3000, 8080]` → `:3000 :8080`
/// `[3000, 4000, 5000, 6000]` → `:3000 +3` so wide port lists don't blow out
/// the sidebar width.
func lineySidebarListeningPortsBadgeText(_ ports: [Int], maxVisible: Int = 2) -> String {
    let sorted = ports.sorted()
    guard !sorted.isEmpty else { return "" }
    if sorted.count <= maxVisible {
        return sorted.map { ":\($0)" }.joined(separator: " ")
    }
    let visible = sorted.prefix(maxVisible).map { ":\($0)" }.joined(separator: " ")
    let extra = sorted.count - maxVisible
    return "\(visible) +\(extra)"
}
