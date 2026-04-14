# Remote Folder Selection UI Highlight

## Problem

When browsing remote directories in `RemoteDirectoryBrowser`, clicking a folder updates `selectedPath` and the bottom bar displays it, but the folder row itself has no visual highlight. Users cannot tell which folder is currently selected.

## Reference

Treemux's `DirectoryNodeRow` implements this with a `@Binding var selectedPath: String?` and a `RoundedRectangle` background that fills with `Color.accentColor.opacity(0.2)` when selected.

## Design

Use LineyTheme's existing sidebar selection colors (`sidebarSelectionFill` + `sidebarSelectionStroke`) for consistency with the app's selection style.

### Changes

**File: `RemoteDirectoryBrowser.swift`**

1. **`DirectoryRowView` struct** — add `@Binding var selectedPath: String?`, computed `isSelected` property. Replace direct viewModel mutation with binding write.
2. **Label styling** — wrap label in `RoundedRectangle(cornerRadius: 4)` background with `sidebarSelectionFill` when selected, `sidebarSelectionStroke` border when selected. Change icon to `folder.fill` with blue color.
3. **Recursive binding** — pass `$selectedPath` to child `DirectoryRowView` instances.
4. **Parent view** — pass `$viewModel.selectedPath` when creating root `DirectoryRowView`.

**File: `RemoteDirectoryBrowserViewModel.swift`**

5. **`selectedPath` type** — change from `String = ""` to `String? = nil`.

**File: `RemoteDirectoryBrowser.swift` (bottom bar)**

6. **Bottom bar** — adjust to handle optional `selectedPath` (display when non-nil, disable Open when nil).
