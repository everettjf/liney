//
//  WorkspacePreviewPanel.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

/// The right-hand panel that renders the workspace's current preview content:
/// a rendered Markdown / HTML file, or a live web page served on the host.
struct WorkspacePreviewPanel: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var engine = PreviewWebEngine()

    let content: WorkspacePreviewContent
    /// Live-reload files when they change on disk.
    var liveReload: Bool = true
    let onNavigate: (WorkspacePreviewContent) -> Void
    let onClose: () -> Void

    @State private var addressText = ""
    @State private var isEditingAddress = false
    @State private var watcher: FileChangeWatcher?

    private func localized(_ key: String) -> String { localization.string(key) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LineyTheme.border)
            ZStack {
                LineyTheme.paneBackground
                PreviewWebView(engine: engine)

                if let error = engine.lastError {
                    errorOverlay(error)
                }
            }
        }
        .background(LineyTheme.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onAppear {
            addressText = webAddressString
            loadCurrentContent()
            installWatcherIfNeeded()
        }
        .onChange(of: content) { _, _ in
            addressText = webAddressString
            loadCurrentContent()
            installWatcherIfNeeded()
        }
        .onChange(of: engine.currentURL) { _, newValue in
            if content.isWeb, !isEditingAddress, let newValue {
                addressText = newValue.absoluteString
            }
        }
        .onDisappear {
            watcher?.stop()
            watcher = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if content.isWeb {
                    navButton("chevron.left", enabled: engine.canGoBack) { engine.goBack() }
                    navButton("chevron.right", enabled: engine.canGoForward) { engine.goForward() }
                }

                Image(systemName: content.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LineyTheme.accent)

                if content.isWeb {
                    addressField
                } else {
                    fileTitle
                }

                Spacer(minLength: 4)

                if engine.isLoading {
                    navButton("xmark", enabled: true) { engine.stopLoading() }
                } else {
                    navButton("arrow.clockwise", enabled: true) { reload() }
                }
                navButton("arrow.up.right.square", enabled: true) { openExternally() }
                navButton("xmark.circle.fill", enabled: true, tint: LineyTheme.mutedText) { onClose() }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            if engine.isLoading, engine.estimatedProgress < 1 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(LineyTheme.accent)
                        .frame(width: proxy.size.width * CGFloat(engine.estimatedProgress))
                        .animation(.easeOut(duration: 0.2), value: engine.estimatedProgress)
                }
                .frame(height: 2)
            }
        }
        .background(LineyTheme.paneHeaderBackground)
    }

    private var fileTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LineyTheme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addressField: some View {
        TextField(localized("preview.web.addressPlaceholder"), text: $addressText)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(LineyTheme.tertiaryText)
            .onSubmit { navigateToAddress() }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LineyTheme.sidebarSearchBackground, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(LineyTheme.border, lineWidth: 1)
            )
            .onTapGesture { isEditingAddress = true }
    }

    private func navButton(_ symbol: String, enabled: Bool, tint: Color = LineyTheme.secondaryText, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? tint : LineyTheme.mutedText.opacity(0.4))
        .disabled(!enabled)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(LineyTheme.warning)
            Text(localized("preview.web.loadFailed"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LineyTheme.tertiaryText)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(LineyTheme.mutedText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(localized("preview.web.retry")) { reload() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(LineyTheme.panelRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(LineyTheme.border, lineWidth: 1))
    }

    // MARK: - Content loading

    private var webAddressString: String {
        if case let .web(url) = content { return url.absoluteString }
        return ""
    }

    private func loadCurrentContent() {
        switch content {
        case let .web(url):
            engine.load(remoteURL: url)
        case let .file(url):
            renderFile(url)
        }
    }

    private func renderFile(_ url: URL) {
        switch WorkspacePreviewContent.fileRenderMode(for: url) {
        case .markdown:
            let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let html = MarkdownToHTMLRenderer.renderDocument(markdown, title: url.lastPathComponent)
            engine.load(htmlString: html, baseURL: url.deletingLastPathComponent())
        case .html:
            engine.load(fileURL: url)
        case .none:
            break
        }
    }

    private func installWatcherIfNeeded() {
        watcher?.stop()
        watcher = nil
        guard liveReload, case let .file(url) = content else { return }
        watcher = FileChangeWatcher(url: url) {
            renderFile(url)
        }
    }

    private func reload() {
        switch content {
        case .web:
            engine.reloadIgnoringCache()
        case let .file(url):
            renderFile(url)
        }
    }

    private func navigateToAddress() {
        isEditingAddress = false
        guard let url = WorkspacePreviewContent.webURL(fromUserInput: addressText) else { return }
        onNavigate(.web(url))
    }

    private func openExternally() {
        switch content {
        case let .web(url):
            NSWorkspace.shared.open(engine.currentURL ?? url)
        case let .file(url):
            NSWorkspace.shared.open(url)
        }
    }
}
