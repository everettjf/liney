//
//  CommandPaletteView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    @FocusState private var isSearchFocused: Bool

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var uiScale: CGFloat {
        CGFloat(store.appSettings.uiScale)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    store.dispatch(.toggleCommandPalette)
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .foregroundStyle(LineyTheme.mutedText)
                    TextField(
                        localized("main.commandPalette.searchPlaceholder"),
                        text: Binding(
                            get: { store.commandPaletteQuery },
                            set: { store.updateCommandPaletteQuery($0) }
                        )
                    )
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .focused($isSearchFocused)
                        .onSubmit {
                            store.activateSelectedCommandPaletteItem()
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .overlay(LineyTheme.border)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if store.commandPaletteSections.allSatisfy({ $0.items.isEmpty }) {
                            Text(localized("main.commandPalette.noMatches"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LineyTheme.mutedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        } else {
                            ForEach(store.commandPaletteSections) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.group.title.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(LineyTheme.mutedText)
                                        .padding(.horizontal, 8)

                                    ForEach(section.items) { item in
                                        Button {
                                            activate(item)
                                        } label: {
                                            CommandPaletteRow(
                                                item: item,
                                                isSelected: item.id == store.selectedCommandPaletteItemID
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 380)
            }
            .frame(width: 640)
            .background(LineyTheme.canvasBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LineyTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
            .scaleEffect(uiScale)
        }
        .task {
            isSearchFocused = true
            store.updateCommandPaletteQuery(store.commandPaletteQuery)
        }
        .background(CommandPaletteEventMonitor())
    }

    private func activate(_ item: CommandPaletteItem) {
        store.selectedCommandPaletteItemID = item.id
        store.activateSelectedCommandPaletteItem()
    }
}

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LineyTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LineyTheme.subtleFill.opacity(isSelected || isHovering ? 1 : 0))
        )
        .onHover { isHovering = $0 }
    }

    private var iconName: String {
        switch item.group {
        case .recent:
            return "clock.arrow.circlepath"
        case .navigation:
            return "square.grid.2x2"
        case .sessions:
            return "terminal"
        case .automation:
            return "bolt.fill"
        case .releases:
            return "shippingbox.fill"
        case .workflows:
            return "play.circle.fill"
        case .github:
            return "arrow.triangle.pull"
        }
    }

    private var iconColor: Color {
        switch item.group {
        case .recent:
            return LineyTheme.mutedText
        case .navigation:
            return LineyTheme.localAccent
        case .sessions:
            return LineyTheme.accent
        case .automation:
            return LineyTheme.warning
        case .releases:
            return LineyTheme.danger
        case .workflows:
            return LineyTheme.success
        case .github:
            return LineyTheme.accent
        }
    }
}

private struct CommandPaletteEventMonitor: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var store: WorkspaceStore
        private var monitor: Any?

        init(store: WorkspaceStore) {
            self.store = store
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.store.isCommandPalettePresented else { return event }
                switch event.keyCode {
                case 125:
                    self.store.moveCommandPaletteSelection(delta: 1)
                    return nil
                case 126:
                    self.store.moveCommandPaletteSelection(delta: -1)
                    return nil
                case 36, 76:
                    self.store.activateSelectedCommandPaletteItem()
                    return nil
                case 53:
                    self.store.dispatch(.toggleCommandPalette)
                    return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
