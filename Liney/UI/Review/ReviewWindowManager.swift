import AppKit
import SwiftUI

@MainActor
final class ReviewWindowManager: NSObject, NSWindowDelegate {
    static let shared = ReviewWindowManager()

    let state = ReviewWindowState()
    private var window: NSWindow?

    private override init() {}

    func show(repositoryPath: String?, repositoryName: String) {
        let displayName = ReviewRepositoryDisplayName.resolve(repositoryName)
        state.load(repositoryPath: repositoryPath, repositoryName: displayName)

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: ReviewWindowContentView(state: state).preferredColorScheme(.dark)
        )
        hostingController.sizingOptions = []

        let window = NSWindow(contentViewController: hostingController)
        window.title = displayName.isEmpty ? "Review" : "Review — \(displayName)"
        window.identifier = NSUserInterfaceItemIdentifier("liney.review")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 640)
        window.setFrameAutosaveName("LineyReviewWindow")
        if UserDefaults.standard.string(forKey: "NSWindow Frame LineyReviewWindow") == nil {
            window.setContentSize(NSSize(width: 1040, height: 720))
            window.center()
        }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        state.cancel()
        window = nil
    }
}
