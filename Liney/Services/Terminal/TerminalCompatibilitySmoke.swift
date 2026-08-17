//
//  TerminalCompatibilitySmoke.swift
//  Liney
//

import AppKit
import Foundation

/// A short-lived runtime harness used by the macOS 14 CI runner. Unlike the
/// normal startup smoke test, this creates a real Ghostty surface, resizes it,
/// reads both viewport and scrollback, and tears it down.
@MainActor
enum TerminalCompatibilitySmoke {
    static func run() -> Int32 {
        _ = NSApplication.shared
        TerminalDiagnostics.shared.clear()

        let paneID = UUID()
        let sessionID = UUID()
        let configuration = TerminalLaunchConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            environment: ProcessInfo.processInfo.environment,
            command: TerminalCommandDefinition(
                executablePath: "/bin/zsh",
                // Keep the shell alive long enough for slower CI machines to
                // initialize and resize the surface. The harness terminates it
                // immediately after observing the marker, so this does not add
                // five seconds to successful runs.
                arguments: ["-f", "-c", "printf 'liney-compatibility-smoke\\n'; sleep 5"],
                displayName: "compatibility-smoke"
            ),
            backendConfiguration: .local(),
            initialInput: nil,
            diagnosticPaneID: paneID,
            diagnosticSessionID: sessionID
        )
        let controller = LineyGhosttyController(launchConfiguration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        window.orderFront(nil)
        controller.startManagedSessionIfNeeded()

        guard controller.currentSurface != nil else {
            return fail("surface was not created")
        }

        for size in [
            NSSize(width: 640, height: 400),
            NSSize(width: 800, height: 500),
            NSSize(width: 720, height: 360),
        ] {
            window.setContentSize(size)
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        var viewport = ""
        var scrollback = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            viewport = controller.readScreenText(scrollback: false) ?? ""
            scrollback = controller.readScreenText(scrollback: true) ?? ""
            if viewport.contains("liney-compatibility-smoke")
                || scrollback.contains("liney-compatibility-smoke") {
                break
            }
        }

        let preDestroyEvents = TerminalDiagnostics.shared.entries
        guard preDestroyEvents.contains(where: { $0.message.contains("event=surface-create") }) else {
            return fail("surface-create diagnostic was not recorded")
        }
        guard preDestroyEvents.contains(where: { $0.message.contains("event=metrics") }) else {
            return fail("resize metrics diagnostic was not recorded")
        }
        guard preDestroyEvents.contains(where: { $0.message.contains("event=screen-read") }) else {
            return fail("screen-read diagnostic was not recorded")
        }
        guard viewport.contains("liney-compatibility-smoke")
                || scrollback.contains("liney-compatibility-smoke") else {
            return fail("terminal output was not readable")
        }

        controller.terminateManagedSession()
        window.orderOut(nil)
        guard controller.currentSurface == nil else {
            return fail("surface was not destroyed")
        }
        guard TerminalDiagnostics.shared.entries.contains(where: {
            $0.message.contains("event=surface-destroy")
        }) else {
            return fail("surface-destroy diagnostic was not recorded")
        }

        FileHandle.standardOutput.write(Data("LINEY_TERMINAL_COMPATIBILITY_SMOKE_OK\n".utf8))
        return 0
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("Liney terminal compatibility smoke failed: \(message)\n".utf8))
        return 1
    }
}
