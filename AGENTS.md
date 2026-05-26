# Liney Repository Collaboration Guide

## 交流语言 / Communication Language

**始终使用简体中文回复。** 无论用户使用何种语言提问,所有面向用户的回复、解释和总结都必须用简体中文。代码、标识符、命令、文件路径以及代码内的注释保持原样(通常为英文),不要翻译。

**Always reply in Simplified Chinese.** Regardless of the language the user writes in, all user-facing responses, explanations, and summaries must be in Simplified Chinese. Keep code, identifiers, commands, file paths, and in-code comments as-is (usually English); do not translate them.

## Project Overview

Liney is a native macOS terminal workspace app built around `AppKit + SwiftUI + a vendored Ghostty runtime`.
The core product experience centers on a multi-repository sidebar, worktree switching, terminal pane and tab layout restoration, diff and overview helper views, and GitHub and update-related features.

The repository now uses an Xcode project as the primary development entry point. The root still contains release scripts, docs, website code, and local build artifacts.

## Repository Layout

- `Liney/`: Main application source root.
- `Liney/App/`: App assembly and high-level state orchestration. Start with `WorkspaceStore.swift`, `LineyDesktopApplication.swift`, and `WorkspaceGitHubCoordinator.swift`.
- `Liney/Domain/`: Domain models for workspaces, pane layouts, tabs, and related state.
- `Liney/Persistence/`: Workspace state, settings persistence, and migrations.
- `Liney/Services/Git/`: Git repository inspection, worktree discovery, GitHub CLI integration, and metadata watching.
- `Liney/Services/Process/`: Subprocess execution wrappers.
- `Liney/Services/Terminal/`: Terminal sessions, Ghostty bridge code, and surface/controller lifecycle management.
- `Liney/Services/Updates/`: Sparkle update checks and install flow entry points.
- `Liney/Support/`: Menus, commands, path formatting, external editor support, sleep prevention, and shared UI state.
- `Liney/UI/Sidebar/`: Left sidebar tree and bridge logic. The key file is `WorkspaceSidebarView.swift`.
- `Liney/UI/Workspace/`: Workspace detail views, pane containers, and terminal pane UI.
- `Liney/UI/Overview/`: Repository overview and desk views plus their view model.
- `Liney/UI/Diff/`: Diff window state, rendering, and changed-file models.
- `Liney/UI/Canvas/`: Global canvas-style UI.
- `Liney/UI/Sheets/`: Sheets for creating worktrees, SSH sessions, agent sessions, settings, and related flows.
- `Liney/UI/Components/`: Reusable UI components such as the command palette, terminal host, and toolbar icons.
- `Liney/Vendor/`: Vendored `GhosttyKit.xcframework`. Do not modify this without explicit need.
- `Tests/`: Unit tests covering git parsing, pane layout, terminal sessions, Ghostty input support, overview, diff, workspace tabs and settings, and related logic.
- `docs/`: Maintainer documentation such as testing and terminal architecture notes.
- `scripts/`: Local build, signing, release, Sparkle, and Homebrew publishing scripts.
- `website/`: Website source, separate from the macOS app project.
- `dist/`: Local build artifacts. Usually not edited directly.

## Build And Test

Use the root `Liney.xcodeproj` by default:

```sh
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Run tests with:

```sh
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Additional notes:

- The current project targets are `Liney` and `LineyTests`, and the main scheme is `Liney`.
- Dependencies are resolved through Xcode. Current Swift packages include Sparkle and Sentry.
- Release-oriented scripts include `scripts/build_macos_app.sh`, `scripts/release_macos.sh`, and the root `deploy.sh`. They depend on signing, notarization, or release credentials and are not the default verification path for routine changes.
- Documentation, script, or website changes do not automatically require a full app build, but command examples, paths, and references must remain valid.

## Testing And Verification

- After UI, state-management, terminal lifecycle, or update-flow changes, run at least one `xcodebuild ... build`.
- For git, worktree, layout, diff, overview, or settings logic changes, prefer adding or updating focused unit tests under `Tests/`.
- For terminal input, keyboard shortcut, IME, or Ghostty adapter changes, pay special attention to `Tests/LineyGhosttyInputSupportTests.swift` and `Tests/ShellSessionTests.swift`.
- For changes affecting the sidebar, pane layout, worktree switching, command palette, diff windows, or external editor integration, include a brief manual smoke test and state what was covered.
- For documentation-only changes, at minimum verify that referenced files still exist and command examples still match the current project layout.

## Code Hotspots

- `Liney/App/WorkspaceStore.swift`: Main orchestration entry point for user actions, including repository refresh, worktree switching, and pane or tab management.
- `Liney/UI/Sidebar/WorkspaceSidebarView.swift`: Sidebar tree, search, multi-selection, context menus, and drag reordering.
- `Liney/UI/Workspace/WorkspaceDetailView.swift`: Main workspace detail view and pane container.
- `Liney/Services/Git/GitRepositoryService.swift`: Git status parsing, branch information, and worktree inspection.
- `Liney/Services/Terminal/`: Session launch, Ghostty runtime integration, and terminal surface/controller logic. Confirm AppKit integration is preserved before making changes here.
- `Liney/UI/Overview/OverviewViewModel.swift`: Overview data shaping and derived state.
- `Liney/UI/Diff/DiffRendering.swift`: Core diff rendering logic. Review diff-related tests when changing it.
- `Liney/Services/Updates/AppUpdaterController.swift`: Sparkle update entry point.
- `Liney/Support/QuickCommandSupport.swift` and `Liney/UI/Components/CommandPaletteView.swift`: Command palette and quick-command behavior.

## Modification Conventions

- Preserve the existing `AppKit container + SwiftUI content` architecture. Do not rewrite major UI sections for small changes.
- The sidebar relies on a custom `NSOutlineView` bridge. Changes there must not break multi-selection, context menus, keyboard interaction, or drag reordering.
- The terminal stack depends on the vendored Ghostty runtime and the adapters under `Liney/Services/Terminal/Ghostty/`. Do not introduce an alternate terminal implementation.
- Unless explicitly required, do not modify binary dependencies under `Liney/Vendor/` or casually alter signing and notarization behavior in release scripts.
- For GitHub CLI, Sparkle, Sentry, or external-editor-related work, prefer the existing service or support-layer entry points instead of scattering process execution logic into the UI layer.
- If code changes invalidate directory descriptions, build commands, test entry points, or release paths, update `README.md`, `DEVELOP.md`, `docs/`, `RELEASING.md`, or nearby script comments so documentation does not drift.
