//
//  IslandContentView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct IslandContentView: View {
    @ObservedObject var state: IslandNotificationState
    let controller: IslandPanelController

    var body: some View {
        Group {
            if state.isExpanded {
                IslandExpandedView(state: state, controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else {
                IslandCollapsedView(state: state)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                state.isExpanded.toggle()
            }
            controller.repositionPanel()
        }
    }
}
