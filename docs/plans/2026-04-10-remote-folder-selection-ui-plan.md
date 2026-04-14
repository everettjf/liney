# Remote Folder Selection UI Highlight — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add visual selection highlight to remote directory browser rows so users can see which folder is selected.

**Architecture:** Add a `@Binding var selectedPath: String?` to `DirectoryRowView`, use `LineyTheme.sidebarSelectionFill` / `sidebarSelectionStroke` for the highlight background, and change the ViewModel's `selectedPath` to `String?` for cleaner nil semantics.

**Tech Stack:** SwiftUI, LineyTheme

---

### Task 1: Change ViewModel selectedPath to Optional

**Files:**
- Modify: `Liney/UI/Sheets/RemoteDirectoryBrowserViewModel.swift:47`

**Step 1: Change selectedPath type**

Change line 47 from:
```swift
@Published var selectedPath: String = ""
```
to:
```swift
@Published var selectedPath: String? = nil
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Liney -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Build errors in `RemoteDirectoryBrowser.swift` (expected — we fix those in Task 2).

**Step 3: Commit**

```bash
git add Liney/UI/Sheets/RemoteDirectoryBrowserViewModel.swift
git commit -m "refactor: change selectedPath to Optional<String> for nil semantics"
```

---

### Task 2: Rewrite DirectoryRowView with selection binding and highlight

**Files:**
- Modify: `Liney/UI/Sheets/RemoteDirectoryBrowser.swift:10-50`

**Step 1: Replace entire `DirectoryRowView` struct**

Replace lines 10-50 (the full `DirectoryRowView` struct) with:

```swift
private struct DirectoryRowView: View {
    @ObservedObject var node: DirectoryNode
    @Binding var selectedPath: String?
    let expandAction: (DirectoryNode) async -> Void

    private var isSelected: Bool {
        selectedPath == node.path
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { node.isExpanded },
            set: { newValue in
                if newValue {
                    Task { await expandAction(node) }
                } else {
                    node.isExpanded = false
                }
            }
        )) {
            if node.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 8)
            } else if let error = node.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else {
                ForEach(node.children) { child in
                    DirectoryRowView(
                        node: child,
                        selectedPath: $selectedPath,
                        expandAction: expandAction
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 13))
                Text(node.name)
                    .lineLimit(1)
                    .font(.system(size: 13))
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color(nsColor: LineyTheme.sidebarSelectionFill) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? Color(nsColor: LineyTheme.sidebarSelectionStroke) : Color.clear, lineWidth: 1)
            )
            .onTapGesture {
                selectedPath = node.path
            }
        }
    }
}
```

Key changes from original:
- `viewModel: RemoteDirectoryBrowserViewModel` replaced by `@Binding var selectedPath: String?` + `expandAction` closure
- Added `isSelected` computed property
- Label uses `folder.fill` icon with blue color
- Background uses `LineyTheme.sidebarSelectionFill` when selected
- Overlay uses `LineyTheme.sidebarSelectionStroke` border when selected
- Recursive children pass `$selectedPath` binding

**Step 2: Commit**

```bash
git add Liney/UI/Sheets/RemoteDirectoryBrowser.swift
git commit -m "feat: add selection highlight to DirectoryRowView"
```

---

### Task 3: Update parent view to pass binding and fix bottom bar

**Files:**
- Modify: `Liney/UI/Sheets/RemoteDirectoryBrowser.swift:142-146` (content area)
- Modify: `Liney/UI/Sheets/RemoteDirectoryBrowser.swift:191-217` (bottom bar)

**Step 1: Update DirectoryRowView creation in contentArea**

In the `.connected` case, change the `ForEach` (around lines 143-145) from:
```swift
ForEach(viewModel.rootNodes) { node in
    DirectoryRowView(node: node, viewModel: viewModel)
}
```
to:
```swift
ForEach(viewModel.rootNodes) { node in
    DirectoryRowView(
        node: node,
        selectedPath: $viewModel.selectedPath,
        expandAction: { n in
            await viewModel.expandNode(n)
        }
    )
}
```

**Step 2: Update bottomBar to handle optional selectedPath**

Replace the bottom bar (around lines 191-217) from:
```swift
private var bottomBar: some View {
    HStack {
        Text(viewModel.selectedPath)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(LineyTheme.secondaryText)
            .lineLimit(1)
            .truncationMode(.middle)

        Spacer()

        Button(localized("common.cancel")) {
            Task { await viewModel.disconnect() }
            dismiss()
        }

        Button(localized("remote.browser.open")) {
            let path = viewModel.selectedPath
            Task { await viewModel.disconnect() }
            onSelect(path)
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.selectedPath.isEmpty)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```
to:
```swift
private var bottomBar: some View {
    HStack {
        if let selected = viewModel.selectedPath {
            Text(selected)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LineyTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text(localized("remote.browser.noSelection"))
                .font(.system(size: 11))
                .foregroundStyle(LineyTheme.mutedText)
        }

        Spacer()

        Button(localized("common.cancel")) {
            Task { await viewModel.disconnect() }
            dismiss()
        }

        Button(localized("remote.browser.open")) {
            if let path = viewModel.selectedPath {
                Task { await viewModel.disconnect() }
                onSelect(path)
                dismiss()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.selectedPath == nil)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```

**Step 3: Build to verify everything compiles**

Run: `xcodebuild build -scheme Liney -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Liney/UI/Sheets/RemoteDirectoryBrowser.swift
git commit -m "feat: wire up selection binding and update bottom bar for optional selectedPath"
```
