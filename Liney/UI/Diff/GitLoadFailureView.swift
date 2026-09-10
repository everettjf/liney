import SwiftUI
import YiTong

struct GitLoadFailureView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(title, systemImage: "exclamationmark.triangle", description: Text(message))
            Button(LocalizationManager.shared.string("git.loading.retry"), action: retry)
        }
        .padding()
    }
}

/// Keep renderer startup and failure visible, including when Git already returned a patch.
struct RecoverableDiffView: View {
    let document: DiffDocument
    let configuration: DiffConfiguration
    @State private var rendererID = UUID()
    @State private var hasRendered = false
    @State private var errorMessage: String?

    var body: some View {
        DiffView(document: document, configuration: configuration) { event in
            switch event {
            case .didRender:
                hasRendered = true
                errorMessage = nil
            case .didFail(let error):
                errorMessage = error.message
            default:
                break
            }
        }
        .id(rendererID)
        .overlay {
            if let errorMessage {
                GitLoadFailureView(
                    title: LocalizationManager.shared.string("git.loading.renderFailed"),
                    message: errorMessage,
                    retry: {
                        self.errorMessage = nil
                        hasRendered = false
                        rendererID = UUID()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LineyTheme.canvasBackground)
            } else if !hasRendered {
                ProgressView()
            }
        }
        .task(id: rendererID) {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            if !hasRendered, errorMessage == nil {
                errorMessage = LocalizationManager.shared.string("git.loading.renderTimeout")
            }
        }
    }
}
