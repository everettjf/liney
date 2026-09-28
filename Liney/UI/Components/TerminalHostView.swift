//
//  TerminalHostView.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    @ObservedObject var session: ShellSession
    var shouldRestoreFocus: Bool = false
    var onActivate: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var onActivate: (() -> Void)?
    }

    func makeNSView(context: Context) -> TerminalViewContainer {
        let container = TerminalViewContainer()
        context.coordinator.onActivate = onActivate
        if onActivate != nil {
            let coordinator = context.coordinator
            coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak container, weak coordinator] event in
                if let container, event.window === container.window,
                   !container.isHiddenOrHasHiddenAncestor,
                   container.visibleRect.contains(container.convert(event.locationInWindow, from: nil)) {
                    coordinator?.onActivate?()
                }
                return event
            }
        }
        container.attach(session.nsView, restoreFocus: shouldRestoreFocus)
        return container
    }

    func updateNSView(_ nsView: TerminalViewContainer, context: Context) {
        context.coordinator.onActivate = onActivate
        nsView.attach(session.nsView, restoreFocus: shouldRestoreFocus)
    }

    static func dismantleNSView(_ nsView: TerminalViewContainer, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
        coordinator.onActivate = nil
    }
}

final class TerminalViewContainer: NSView {
    private weak var hostedView: NSView?

    func attach(_ view: NSView, restoreFocus: Bool) {
        let needsAttach = hostedView !== view || view.superview !== self

        if needsAttach {
            hostedView?.removeFromSuperview()
            view.removeFromSuperview()
            hostedView = view
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        guard restoreFocus, needsAttach else { return }
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, let window = self.window ?? view.window else { return }
            if window.firstResponder !== view {
                window.makeFirstResponder(view)
            }
        }
    }
}
