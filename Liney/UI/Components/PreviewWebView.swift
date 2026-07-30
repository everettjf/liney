//
//  PreviewWebView.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import SwiftUI
import WebKit

/// Owns a single `WKWebView` and publishes its navigation state.
///
/// Reused across content changes so a live web page keeps its session while the
/// user navigates. Markdown is handed in as a pre-rendered HTML string; HTML
/// files are loaded from disk with read access to their folder (so relative
/// assets resolve); web pages are loaded over the network the host machine
/// itself uses.
@MainActor
final class PreviewWebEngine: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var pageTitle = ""
    @Published private(set) var currentURL: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var estimatedProgress: Double = 0

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground") // transparent until content paints

        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                let isLoading = webView.isLoading
                Task { @MainActor [weak self] in self?.isLoading = isLoading }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                let canGoBack = webView.canGoBack
                Task { @MainActor [weak self] in self?.canGoBack = canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                let canGoForward = webView.canGoForward
                Task { @MainActor [weak self] in self?.canGoForward = canGoForward }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                let estimatedProgress = webView.estimatedProgress
                Task { @MainActor [weak self] in self?.estimatedProgress = estimatedProgress }
            },
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                let pageTitle = webView.title ?? ""
                Task { @MainActor [weak self] in self?.pageTitle = pageTitle }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                let currentURL = webView.url
                Task { @MainActor [weak self] in self?.currentURL = currentURL }
            },
        ]
    }

    // MARK: - Loading

    func load(htmlString: String, baseURL: URL?) {
        lastError = nil
        webView.loadHTMLString(htmlString, baseURL: baseURL)
    }

    func load(fileURL: URL) {
        lastError = nil
        let directory = fileURL.deletingLastPathComponent()
        webView.loadFileURL(fileURL, allowingReadAccessTo: directory)
    }

    func load(remoteURL: URL) {
        lastError = nil
        webView.load(URLRequest(url: remoteURL))
    }

    func reload() {
        lastError = nil
        webView.reload()
    }

    func reloadIgnoringCache() {
        lastError = nil
        webView.reloadFromOrigin()
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func stopLoading() { webView.stopLoading() }
}

extension PreviewWebEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastError = nil
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        // -999 is "cancelled" (e.g. a superseded navigation); not worth surfacing.
        guard nsError.code != NSURLErrorCancelled else { return }
        lastError = nsError.localizedDescription
    }
}

/// SwiftUI host that mounts a `PreviewWebEngine`'s web view.
struct PreviewWebView: NSViewRepresentable {
    @ObservedObject var engine: PreviewWebEngine

    func makeNSView(context: Context) -> WKWebView {
        engine.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
