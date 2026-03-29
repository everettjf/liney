//
//  FeatureExtensionRegistry.swift
//  Liney
//

import Foundation

struct LineyExtensionContext {
    let selectedWorkspace: WorkspaceModel?
    let workspaces: [WorkspaceModel]
}

protocol LineyFeatureExtension {
    var id: String { get }
    func commandPaletteItems(context: LineyExtensionContext) -> [CommandPaletteItem]
}

struct SupportLinksExtension: LineyFeatureExtension {
    let id = "support-links"

    func commandPaletteItems(context: LineyExtensionContext) -> [CommandPaletteItem] {
        _ = context
        return [
            CommandPaletteItem(
                id: "extension-support-website",
                title: LocalizationManager.shared.string("extension.support.website"),
                subtitle: "liney.dev",
                group: .navigation,
                keywords: ["extension", "help", "website", "docs"],
                isGlobal: true,
                kind: .command(.openLineyWebsite)
            ),
            CommandPaletteItem(
                id: "extension-support-feedback",
                title: LocalizationManager.shared.string("extension.support.feedback"),
                subtitle: "github.com/everettjf/liney/issues/new",
                group: .navigation,
                keywords: ["extension", "feedback", "issue", "bug"],
                isGlobal: true,
                kind: .command(.submitLineyFeedback)
            )
        ]
    }
}

final class LineyFeatureRegistry {
    static let shared = LineyFeatureRegistry(extensions: [
        SupportLinksExtension()
    ])

    private(set) var extensions: [any LineyFeatureExtension]

    init(extensions: [any LineyFeatureExtension] = []) {
        self.extensions = extensions
    }

    func register(_ featureExtension: any LineyFeatureExtension) {
        guard !extensions.contains(where: { $0.id == featureExtension.id }) else { return }
        extensions.append(featureExtension)
    }

    func commandPaletteItems(context: LineyExtensionContext) -> [CommandPaletteItem] {
        extensions.flatMap { $0.commandPaletteItems(context: context) }
    }
}
