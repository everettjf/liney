//
//  IslandCollapsedView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct IslandCollapsedView: View {
    @ObservedObject var state: IslandNotificationState

    var body: some View {
        HStack(spacing: 10) {
            if let item = state.latestItem {
                islandStatusIcon(for: item)
                    .font(.system(size: 14))

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if state.badgeCount > 1 {
                    Text("\(state.badgeCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.15))
                        )
                }
            } else {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))

                Text("Liney")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

@ViewBuilder
func islandStatusIcon(for item: IslandNotificationItem) -> some View {
    switch item.status {
    case .running:
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
    case .done:
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
    case .error:
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
    case .waitingForInput:
        Image(systemName: "questionmark.circle.fill")
            .foregroundStyle(.cyan)
    }
}
