#if DEBUG
import AppKit
import SwiftUI

/// Isolated, real-surface acceptance fixture. Never loads the user's workspaces.
@MainActor
enum WorkbenchSmoke {
    static func run(interactive: Bool) -> Int32 {
        let app = NSApplication.shared
        // Ghostty filters stdout asynchronously; retain a direct result channel.
        let output = FileHandle(fileDescriptor: dup(STDOUT_FILENO), closeOnDealloc: true)
        TerminalDiagnostics.shared.clear()
        app.setActivationPolicy(.regular)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liney-workbench-\(UUID().uuidString)")
        let persistence = WorkspacePersistenceCoordinator(
            workspacePersistence: WorkspaceStatePersistence(stateDirectoryURL: directory),
            settingsPersistence: AppSettingsPersistence(stateDirectoryURL: directory)
        )
        let store = WorkspaceStore(persistsWorkspaceState: true, persistenceCoordinator: persistence,
            terminalHistoryCoordinator: TerminalHistoryCoordinator(persistence: TerminalHistoryPersistence(directory: directory.appendingPathComponent("history"))))
        for index in 1...12 {
            let workspace = store.createStandaloneTerminal(at: NSTemporaryDirectory())
            workspace.name = "Terminal \(index)"
        }
        guard let first = store.workspaces.first, let paneID = first.paneOrder.first else { return 1 }
        AgentStatusStore.shared.update(pane: paneID, state: .waiting, title: "Choose the migration strategy")
        store.isCanvasPresented = true
        let hosting = NSHostingController(rootView: WorkbenchSmokeRoot().environmentObject(store))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Liney Workbench Acceptance"
        window.setContentSize(NSSize(width: 1280, height: 850))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        if interactive {
            output.write(Data("WORKBENCH_FIXTURE \(directory.path)\n".utf8))
            app.run()
            return 0
        }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
        settle()
        let sessions = store.workspaces.flatMap { $0.sessionController.sessions.values }
        let identities = sessions.map { ObjectIdentifier($0) }
        let pids = sessions.map(\.pid)
        let surfaceCount = TerminalDiagnostics.shared.entries.filter { $0.message.contains("event=surface-create") }.count
        store.isCanvasPresented = false
        store.isOverviewPresented = true
        settle()
        store.isOverviewPresented = false
        store.isCanvasPresented = true
        settle()
        let after = store.workspaces.flatMap { $0.sessionController.sessions.values }
        let finalSurfaceCount = TerminalDiagnostics.shared.entries.filter { $0.message.contains("event=surface-create") }.count
        let unchanged = identities == after.map { ObjectIdentifier($0) } && pids == after.map(\.pid)
            && surfaceCount == finalSurfaceCount && surfaceCount == 12
        store.persist()
        store.flushPendingPersistence()
        let restored = persistence.loadWorkspaceState().value
        let valid = unchanged && restored.workspaces.count == 12 && restored.workspaces.allSatisfy(\.settings.isStandaloneTerminal)
        window.orderOut(nil)
        sessions.forEach { $0.terminate() }
        output.write(Data("surfaces=\(surfaceCount) after=\(finalSurfaceCount) sessions=\(sessions.count) restored=\(restored.workspaces.count)\n".utf8))
        output.write(Data(((valid ? "LINEY_WORKBENCH_SMOKE_OK" : "LINEY_WORKBENCH_SMOKE_FAILED") + "\n").utf8))
        return valid ? 0 : 1
    }
}

private struct WorkbenchSmokeRoot: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Overview") { store.isCanvasPresented = false; store.isOverviewPresented = true }
                Button("Canvas") { store.isOverviewPresented = false; store.isCanvasPresented = true }
                Button("Workspace") { store.isOverviewPresented = false; store.isCanvasPresented = false }
                Button("New Terminal") { store.createStandaloneTerminal() }.keyboardShortcut("t", modifiers: [.command, .shift])
            }.padding(8)
            if store.isOverviewPresented {
                OverviewView { store.isOverviewPresented = false }
            } else if store.isCanvasPresented {
                GlobalCanvasView { store.isCanvasPresented = false }
            } else {
                HStack(spacing: 0) {
                    WorkspaceSidebarView().frame(width: 240)
                    WorkspaceDetailView()
                }
            }
        }.preferredColorScheme(.dark)
    }
}
#endif
