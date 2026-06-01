# Workbench Panels: File Tree, Preview, and Web

Liney groups file browsing and output viewing into a single optional **right-hand
"workbench" column**, beside the terminal. The far-left workspace sidebar stays
pure project/worktree navigation. The column is workspace-level UI that wraps the
terminal area — the terminal/session/persistence core is untouched, so panels
never participate in pane layout, zoom, or restoration.

The column hosts the directory tree (top) and the preview panel (bottom); either
can appear on its own, and together they share the column via a resizable
vertical split (`VSplitView`).

## Directory tree (right, top)

`WorkspaceFileTreeView` shows a lazy, recursive directory tree whose **root
follows the focused pane's working directory**. Liney's shell integration already
reports `cwd` via OSC 7 (`ShellSession.reportedWorkingDirectory`); the tree
observes the focused session and re-roots whenever you `cd` — or click a
different pane. Loading is driven by a `.task(id:)` keyed on the directory, so the
root and any expanded folder populate on first appear (no manual refresh needed)
and reload when the path, refresh button, or hidden-file toggle changes.

- Shown by default; the **Settings → General → "Show the file tree by default"**
  toggle (`AppSettings.directoryTreeEnabled`, default on) controls the initial
  state, seeded once per workspace the first time it appears so a manual toggle
  is never overridden.
- Toggle at runtime with the toolbar **file-tree** button or the "More actions" menu.
- Click a directory to expand/collapse; click a Markdown/HTML file to open it in
  the preview panel; click any other file to open it in the default app.
- Right-click for: open in preview, `cd` here (injects `cd '<path>'` into the
  focused terminal), reveal in Finder, open with default app, copy path.
- Header buttons: toggle hidden files, refresh, hide.

### Local vs. remote source

The tree's source follows the **focused pane**, not the workspace. The
`DirectoryTreeSource` is derived in `WorkspaceFileTreeView`:

- If the focused pane is an **SSH session** (`backendConfiguration.kind == .ssh`),
  the tree lists that pane's **remote host** over SFTP
  (`RemoteDirectoryConnectionPool` → `SFTPService` `ls`), using the SSH config
  carried by the pane itself. This works even inside an otherwise-local
  workspace, where `workspace.sshTarget` is never set.
- Otherwise it falls back to a remote workspace's `sshTarget`, then to the local
  filesystem.

For a remote (SSH) pane the local worktree path doesn't exist on the remote
host, so the root is resolved in priority order: the remote `cwd` reported by the
shell over OSC 7 (so the tree still tracks `cd` when the remote shell has shell
integration), then the configured remote working directory, then `.` (the remote
login directory). Remote-only entries skip Finder/preview/open actions — `cd` and
copy-path still apply, and dragging inserts the shell-escaped remote path.

## Preview panel (right, bottom)

`WorkspacePreviewPanel` renders the workspace's current `WorkspacePreviewContent`
in a single reused `WKWebView` (`PreviewWebEngine`):

- **Markdown** files are converted to a styled, light/dark-aware HTML document by
  `MarkdownToHTMLRenderer` (a self-contained GFM-subset renderer — no bundled JS)
  and loaded with the file's folder as the base URL so relative images resolve.
- **HTML** files are loaded directly from disk.
- Files **live-reload** on disk changes (`FileChangeWatcher`), so AI-generated
  output refreshes as it is written.

## Web pages (right)

The same panel can load a live web page. Because the `WKWebView` runs in Liney's
process on the host machine, it uses the host's own network — opening
`http://localhost:3000` shows a dev server exactly as a browser on that machine
would. The toolbar **globe** menu lists ports detected by `ListeningPortInspector`
for the focused pane and offers "Open URL…" for anything else. Bare input is
normalized (`:3000` → `http://localhost:3000`).

`Info.plist` enables `NSAllowsLocalNetworking` so insecure `http://localhost`
dev servers load without disabling App Transport Security globally.

## Key types

| Concern | Type | Location |
| --- | --- | --- |
| Preview content model | `WorkspacePreviewContent` | `Liney/Domain/` |
| Markdown → HTML | `MarkdownToHTMLRenderer` | `Liney/Support/` |
| Directory listing | `DirectoryTreeLoader` / `DirectoryTreeEntry` | `Liney/Support/` |
| File live-reload | `FileChangeWatcher` | `Liney/Support/` |
| Web view host | `PreviewWebEngine` / `PreviewWebView` | `Liney/UI/Components/` |
| Preview panel UI | `WorkspacePreviewPanel` | `Liney/UI/Workspace/` |
| File tree UI | `WorkspaceFileTreeView` | `Liney/UI/Workspace/` |
| State | `WorkspaceModel.isFileTreePresented` / `.previewPanel` | `Liney/Domain/WorkspaceRuntime.swift` |
