<!--
  testing.md
  Liney

  Author: everettjf
-->

# Testing Guide

This repository leans on focused unit tests instead of broad integration fixtures. Good tests here should make state transitions and parsing rules obvious, stay cheap to run, and avoid coupling to AppKit rendering details unless the behavior truly depends on them.

## What Good Tests Look Like

- Test one behavior branch at a time.
- Name tests around the user-visible or state-visible outcome.
- Prefer deterministic in-memory fixtures over shelling out or touching real repositories.
- Use small fake collaborators when a service depends on `@MainActor` callbacks or controller protocols.
- Assert the specific state transition that matters, not every field in the object.

## Where Tests Usually Belong

- `Tests/GitRepositoryServiceTests.swift`
  For git output parsing, branch selection, ahead/behind, and worktree discovery.
- `Tests/PaneLayoutTests.swift`
  For split trees, pane movement, zoom state, and layout persistence rules.
- `Tests/ShellSessionTests.swift`
  For session lifecycle, controller callbacks, and launch/restart behavior.
- `Tests/LineyGhosttyInputSupportTests.swift`
  For keyboard routing, modifier translation, IME marked-text helpers, and other pure Ghostty adapter logic.

## Preferred Patterns

### Keep parsing tests string-driven

For git parsing logic, pass raw command output into pure helpers and assert the parsed model. That keeps tests stable and independent from the local machine.

### Use fakes for session/controller tests

`ShellSessionTests` uses a fake `ManagedTerminalSessionSurfaceController` to drive exit callbacks and restart behavior without creating a real terminal surface. Prefer this style whenever the unit under test only needs protocol conformance.

### Isolate pure terminal adapter logic

The Ghostty adapter exposes several pure helpers such as:

- `LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent`
- `ghosttyShouldAttemptMenu`
- `resolveGhosttyEquivalentKey`
- `LineyGhosttyMarkedTextState`

These are good candidates for direct unit tests because they encode tricky keyboard and IME rules without requiring a live `NSView`.

## Scope Guidelines

- Add or update tests when changing git parsing, worktree behavior, pane layout rules, persistence, command palette ranking, or terminal adapter logic.
- A plain refactor that only renames types or moves files should still keep at least one targeted test run in the verification notes.
- UI-only visual polish does not always need a new unit test, but it should call out any manual smoke test that was performed.

## Running Tests

Run the full test suite:

```bash
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -destination 'platform=macOS' \
  test
```

Run just the Ghostty input-support tests:

```bash
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -destination 'platform=macOS' \
  test \
  -only-testing:LineyTests/LineyGhosttyInputSupportTests
```

CI also maintains an older-system regression matrix:

- Xcode 26.3 builds an arm64 + x86_64 app at the macOS 14.6 deployment target.
- A macOS 14 runner ad-hoc signs that artifact and runs the built-in terminal
  compatibility harness. The harness creates a real Ghostty surface, performs
  multiple resizes, reads viewport and scrollback text, and verifies surface
  teardown plus the corresponding diagnostics.
- macOS 15 with Xcode 26.3 runs the full unit-test suite and exercises Swift
  concurrency back-deployment behavior.

Terminal diagnostics retain one hour of non-input events. Refresh, display
metrics, resize, IME composition lengths, scrollback reads, and session/surface
lifecycle entries include pane and session identifiers. The diagnostics window
can export a report or open a prefilled GitHub issue while revealing the report
file in Finder for attachment.

## Review Checklist

Before sending a test-heavy change for review, check:

- The test fails for the broken behavior and passes for the intended behavior.
- The test names explain the branch being covered.
- Fixtures are local to the file unless they are reused enough to justify extraction.
- The assertions are not overspecified.

## Session history and Git window regression checks

Focused coverage lives in `TerminalHistoryPersistenceTests`,
`GitWindowLoadingTests`, `ShellSessionTests`, and
`WorkspaceStoreTests.testBatchImportDeduplicatesAndGroupsSuccessfulRepositoriesDespiteFailure`.
The `compatibility-smoke` executable subcommand also captures a real Ghostty
surface through `ShellSession` and verifies that its output reaches a history
snapshot in an isolated temporary directory.

For manual verification, use disposable repositories with both committed files
and uncommitted changes:

- Open Diff immediately after launching Liney, and open Git History on a root
  commit. Both should select and display the first file without reopening.
  Refresh, switch repository context, and commit fixture changes; stale content
  should not reappear, and failures must offer a retry.
- Create a group, use **Add Projects… → Choose Folders…** to select several
  component directories including an already-open repository, and verify the
  group count and deduplication. Check collapse/expand, project switching,
  multiselection, context menus, and drag ordering.
- Confirm **Restore terminal history after restart** is off by default. Enable
  it, print a unique marker in a terminal, allow a periodic save, quit and
  relaunch, and use **Previous session history → View History**. The marker must
  be readable and selectable without being executed in the new shell.
- Repeat with multiple panes/tabs and after force-quitting. Only the latest
  snapshot for each pane should survive; output since the last periodic save
  may be lost after a force-quit. Closing a pane/tab removes its history, and
  disabling the setting clears saved snapshots and loaded historical text.

## Stability release regression checks (2026-09-20)

- `WorkspaceFileBrowserSupportTests`: sparse multi-gigabyte files are rejected,
  NUL-containing input is treated as binary, and exact-limit UTF-8 is preserved.
- `WorkspaceStoreTests.testFileBrowserSaveReportsFailureAndSupportsRetry`:
  failed saves return failure so the sheet retains its dirty state; a subsequent
  save can succeed without losing the edited text.
- `GitWindowLoadingTests`: missing added files surface a document error; range
  and blame failures are reported; changing context clears canceled loading flags.

Local verification used Xcode 27: full `build test` passed, and
`compatibility-smoke` printed `LINEY_TERMINAL_COMPATIBILITY_SMOKE_OK`.
The GitHub Actions Xcode 26.3 / macOS 14 and 15 matrix remains a separate gate.

Interactive smoke used a disposable repository at `/tmp/liney-stability-smoke`:
Git History selected the root commit and its first file on opening; temporarily
moving `.git` surfaced a load failure; restoring `.git` and refreshing loaded the
history again. This also exposed a misleading middle-panel “No Changes” state,
which was changed to show the failure. Save-failure behavior is covered by the
store test and UI code review; a full interactive save-failure and sidebar/IME
matrix has not been completed in this pass.
